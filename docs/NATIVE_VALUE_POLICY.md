# Native Value Policy (V2-SC-153)

TruthBounty V2 accounting is **token-denominated**: stake, bonds, rewards, reserves, and treasury
balances are all ERC20 quantities. No canonical V2 contract holds, forwards, or accounts for native
currency. This document is the authoritative inventory of native-value surfaces and the policy each
one follows, and it maps every acceptance criterion of V2-SC-153 to reproducible evidence.

## Policy

1. **Reject unexpected `msg.value`.** Every token-denominated mutation path either is nonpayable by
   the compiler or explicitly reverts when native value is attached.
2. **Proposals are native-value free.** A governance proposal may not carry a native value for any
   operation (`values[i] == 0`). This is enforced when the proposal is created *and* again when it
   executes, so a proposal that predates the policy cannot move native balance either.
3. **Forced native value is inert.** Native currency pushed onto a contract with `SELFDESTRUCT`
   cannot be refused at the EVM level. It must therefore be *excluded* from every accounting
   invariant: no contract reads `address(this).balance`, so forced balance can never increase
   claimable, reserved, reward, stake, bond, or treasury balances, and it grants no voting weight and
   no proposal-threshold credit.
4. **No sweep path.** The protocol deliberately provides no function that transfers forced native
   balance anywhere: a sweep would give forced value economic meaning, which is exactly what the
   policy forbids.

## Inventory of native-value surfaces

Generated from the sources by `node scripts/check-native-value-policy.mjs --report` and pinned in
[`scripts/native-value-policy.json`](../scripts/native-value-policy.json):

| File | Surfaces | Policy |
| --- | --- | --- |
| `contracts/governance/v2/TruthBountyGovernor.sol` | `receive`, `payable`, `msg.value` | Canonical rejection: `receive()` reverts `UnexpectedNativeValue`; both `execute` overloads revert on `msg.value != 0`; proposal values must be zero. |
| `contracts/governance/v2/ITruthBountyGovernor.sol` | `payable` | Interface documentation surface. `execute(uint256)`  keeps its `payable` declaration so the selector and integrator call sites are unchanged; the implementation always reverts on non-zero value. |
| `contracts/upgrade/TimelockOwnedProxyAdmin.sol` | `payable`, `msg.value` | Deployment surface rejection: `upgradeAndCall` refuses attached native value instead of forwarding it into a transparent proxy (which has no path to release it). |
| `contracts/mocks/ReentrancyAttacker.sol` | `receive`, `fallback`, `payable`, `msg.value` | Test-only fixture; never deployed, no accounting meaning. |
| `contracts/mocks/ForcedNativeValueAttacker.sol` | `payable`, `msg.value`, `selfdestruct` | Adversarial test-only fixture used to force native value onto a target. |
| `contracts/Lock.sol` | `payable`, `nativeBalance` | Documented exception: legacy standalone sample, not deployed by any V2 script and not a governed module. Kept out of this change to stay inside the canonical governance/upgrade surface. |

Everything else in `contracts/` and `contracts-vrm/` is free of native-value surfaces, which the
checker verifies in both directions: an undeclared surface fails, and a stale inventory entry fails
too.

## Behaviour by surface

### Governor entry points

| Entry point | Mutability | Native value behaviour |
| --- | --- | --- |
| `receive()` | payable | Always reverts `UnexpectedNativeValue(msg.value)`, for every executor configuration and identically for the implementation and any proxy. |
| `execute(uint256)` | payable | Reverts `UnexpectedNativeValue(msg.value)` before touching proposal state, the timelock queue, or any target. |
| `execute(address[],uint256[],bytes[],bytes32)` | payable | Same rejection; both overloads share `_rejectNativeValue()`. |
| `propose(...)` / `_propose(...)` | nonpayable | Reverts `NativeValueProposalNotAllowed(index, value)` for any non-zero operation value. |
| `_executeOperations(...)` | — | Re-validates operation values, so a proposal created before the policy cannot move native balance. |
| `queue`, `cancel`, `castVote*`, `setGuardian`, `publishManifest` | nonpayable | Compiler-enforced rejection. |

### Upgrade surface

`TimelockOwnedProxyAdmin.upgradeAndCall` keeps the `payable` signature inherited from
`ProxyAdmin` (so the ABI and timelock call sites are unchanged) but reverts
`UnexpectedNativeValue` when value is attached. Forwarding value would credit a transparent proxy
that has no path to release native currency, permanently stranding it outside all accounting.

### Forced native value

ForcedNativeValueAttacker` deploys a helper that self-destructs in the transaction that created it,
which is the only construction that still moves a balance under EJP-6780. That bypasses every
`receive`/`fallback` rejection, which is why the policy's guarantee is *exclusion*, not refusal:

* the forced balance may appear in `address(contract).balance`,
* it cannot appear in any accounting state, because no canonical contract reads
  `address(this).balance`,
* it cannot be claimed, reserved, staked, bonded, rewarded, refunded, or swept by any governance
  path, and it cannot be converted into voting weight.

## Acceptance criteria → evidence

| Acceptance criterion | Evidence |
| --- | --- |
| No canonical operation silently accepts unintended native value. | `test/governance/NativeValueIsolation.t.sol`: `test_DirectNativeTransferIsRejected`, `test_NativeTransferDuringLifecycleIsRejected`, `test_ExecuteByIdRejectsNativeValue`, `test_ExecuteWithOperationsRejectsNativeValue`, `test_ProposalWithNativeValueIsRejected`; plus the inventory checker and its self-tests. |
| Forced ETH never increases claimable, reserved, reward, stake, bond, or treasury balances. | `test_ForcedNativeValueIsEconomicallyInert` asserts the forced balance reaches the contract but changes neither voting weight (`token.balanceOf(governor) == 0`), nor proposer credit (`proposalThreshold()`), nor quorum, and is untouched by a full proposal lifecycle. The policy forbids any native-value proposal operation, so no governance path can disburse it. |
| Documented native-balance behavior is consistent across implementations and proxies. | The unconditional `receive()` rejection does not depend on `_executor()`, so the same behaviour holds for the implementation and for any proxy delegating to it; the upgrade path rejects value instead of forwarding it; this document and `scripts/native-value-policy.json` are the normative inventory. |
| Invariant suites pass under arbitrary forced-balance sequences. | `test_ForcedNativeValueIsEconomicallyInert` and `test_ForcedNativeValueDoesNotLowerProposalBarrier` cover forced balance before and during a lifecycle, including the property that forced balance cannot lower the proposal barrier. |

## Running the checks

```
node scripts/check-native-value-policy.mjs           # inventory + rejection anchors
node --test test/scripts/check-native-value-policy.test.mjs
forge test --match-path "test/governance/NativeValueIsolation.t.sol"
```

The gate is wired into the `lint` job of `.github/workflows/ci.yml`, so a new payable surface, a new
`msg.value` read, a new `address(this).balance` read, or a removed rejection anchor fails CI until the
inventory is updated deliberately.

## Impact notes

* Both `execute` overloads keep their selectors and stay payable at the Solidity level; only the runtime behaviour changes (non-zero value reverts). Existing integrator call sites keep compiling.
* Native funding of a proposal is no longer possible through `execute`. Native payouts were never part of TruthBounty V2 accounting; a module that needs native currency would require an explicit governance change to this policy rather than an implicit transfer.

## Token Behaviour Policy (PREWAVE-SC-053)

TruthBounty V2 accounting is token-denominated, and the supported token set is deliberately narrow.
This section is the normative statement of which ERC20 behaviours are supported, which are
rejected before funds are accepted, and how accounting handles the observed balance delta.

### Supported token behaviours

| Behaviour | Supported? | Rule |
| --- | --- | --- |
| Standard ERC20 with exact transfer semantics | Yes | The default and only fully supported profile. Accounting uses the observed balance delta and asserts it equals the requested amount. |
| False-return (ERC20 returning `false` without reverting) | No | Rejected. Every token interaction uses `safeTransferFrom`/`safeTransfer`/`safeIncreaseAllowance`, which revert on a false return. |
| Missing-return (non-ERC20 token with no boolean return) | No | Rejected. SafeERC20 requires a returned boolean for the address type; a missing return is treated as a failure. |
| Fee-on-transfer | No | Rejected. Accounting observes the receiver delta and reverts with `TokenTransferMismatch` when the delta is less than the requested amount. |
| Rebasing / elastic supply | No | Rejected. Balances are never assumed to be stable across transactions; accounting is delta-based and any unexplained delta is treated as a mismatch and reverted. |
| ERC777-like hooks / re-entrant callbacks | No | Rejected. No canonical path accepts a token whose transfer invokes arbitrary code on the recipient or sender. The governance and treasury surfaces are non-reentrant and assume no token hooks. |
| Blacklisting / pausable tokens | No | Rejected as a supported profile. A token that can freeze or block a participant cannot be used for stake, bonds, or rewards. |
| Decimals extremes (0 or >> 18) | No | Rejected. The protocol assumes `token.decimals|() <= 18` and asserts this at acceptance time; formatting and math use the decimals as a bounded scale factor. |

### Rejection before funds are accepted

An unsupported asset must fail before any funds or stake is accepted. The acceptance check is
performed on the first interaction with a token and reverts with `UnsupportedToken` when any of the
following holds:

1. the token does not return a boolean from `transfer`/`transferFrom`/`approve`,
2. the token returns `false` from a transfer or approval,
3. the observed receiver delta differs from the requested amount (fee-on-transfer or rebase),
4. the token exposes an ERC777-like hook that invokes code on the recipient or sender,
5. the token can blacklist or freeze a participant,
6. `token.decimals()` returns 0 or a value greater than 18.

### Accounting uses observed deltas

Where an asset is accepted, accounting is based on the observed balance delta of the receiver:

```
uint256 before = token.balanceOf(receiver);
token.safeTransferFrom(sender, receiver, amount);
uint256 after = token.balanceOf(receiver);
require(after - before == amount, TokenTransferMismatch());
```

The delta is the only value that enters accounting. A token that delivers less than requested is
rejected and the transaction reverts, so no partial or fee-reduced amount can be recorded.

### Decimals bound

Decimals are read once at acceptance and must satisfy `0 < decimals <= 18`. The scale factor
used for formatting and math is bounded by this range, so `decimals` cannot overflow the
formatting or math assumptions. A token with decimals outside this range is rejected before
any funds are accepted.

### Required tests

| Test | Covers |
| --- | --- |
| `test_SupportedTokenAccepted` | Standard ERC20 with exact transfer semantics is accepted and accounted by delta. |
| `test_FalseReturnTokenRejected` | Token returning `false` is rejected before funds are accepted. |
| `test_MissingReturnTokenRejected` | Token with no boolean return is rejected. |
| `test_FeeOnTransferTokenRejected` | Fee-on-transfer token is rejected by the observed-delta check. |
| test_RebasingTokenRejected` | Rebasing token is rejected when the delta differs from the requested amount. |
| `test_ERC777HookTokenRejected` | Token invoking a recipient hook is rejected. |
| `test_BlacklistTokenRejected` | Token that blacklists a participant is rejected. |
| `test_DecimalsExtremesRejected` | Tokens with `decimals == 0` or `decimals > 18` are rejected. |
| `test_AllowanceRace` | An allowance race cannot move funds beyond the approved amount; accounting observes the delta. |
| `test_TransferMismatchReverts` | A transfer that deliver less than requested reverts with `TokenTransferMismatch`. |
| `test_BalanceDeltaAccounting` | Accounting matches the observed balance delta exactly. |
| `test_RecoveryAfterRejection` | After a rejected asset, the protocol recovers to a consistent state and accepts a supported asset. |

### Policy in manifests and docs

This document is the normative token-behaviour policy. The manifest published by the governor
(`publishManifest`) references this document and the corresponding inventory entry, so the
supported token set is discoverable from both the manifest and the docs. Changing the supported
set requires an explicit governance change to this policy and the manifest.
