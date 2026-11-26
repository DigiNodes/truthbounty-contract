// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PauseMatrix
/// @notice Versioned, explicit pause matrix for the canonical TruthBounty V2 modules (V2-SC-162).
/// @dev Every external state-mutating operation on a canonical V2 module is classified exactly once:
///
///      | Class             | Meaning                                                               | Gate                              |
///      |-------------------|-----------------------------------------------------------------------|-----------------------------------|
///      | `RISK_INCREASING` | Creates new exposure or mutates a not-yet-final outcome (claims,      | Fail closed on every listed scope |
///      |                   | staking, verification, evidence, disputes, settlement, governance).   |                                   |
///      | `NEUTRAL`         | Authority wiring or module-local toggles that neither create exposure | Never scope-gated                 |
///      |                   | nor move value.                                                       |                                   |
///      | `RISK_REDUCING`   | Permissionless exits of value that is already final and owned by the  | Never scope-gated; value exits    |
///      |                   | caller, or protective actions (pausing, nonce cancellation).          | freeze only at protocol SHUTDOWN  |
///
///      Read paths are never gated.
///
///      A gate named `SCOPE_*` fails closed while `IEmergencyControls.paused(scope)` is true, when the
///      pause authority cannot be classified, or when it returns malformed data. The pseudo-gate
///      `EXIT_SHUTDOWN_ONLY` marks a value exit that stays live under every operation-scoped pause and
///      under protocol levels HIGH_RISK / FINANCIAL, and freezes only on an affirmative, healthy
///      `EmergencyController` SHUTDOWN reading (`pull_settled_claim` denied, V2-SC-117). It fails open
///      so that exit liveness never depends on pause-authority or registry health.
///
///      This library is the Solidity mirror of `config/pause-matrix.json`. `scripts/check-pause-matrix.mjs`
///      fails CI if the two disagree, if a module source adds, removes, or re-gates an operation without
///      updating both, or if the version constants differ. Any classification change MUST bump
///      `PAUSE_MATRIX_VERSION` and append a new `history` entry to the JSON matrix.
///
///      Signatures are *source-level* signatures: parameter types exactly as declared in the module
///      source with data locations removed (e.g. `IV2Types.LockCategory`, not `uint8`). They identify
///      operations for review and tests; they are not ABI selectors.
///
///      Every classified operation additionally exposes a canonical, stable operation ID derived from
///      its (module, signature) authority. IDs are namespaced by module and domain-separated so that
///      identical signatures on different modules can never alias, and so that a renamed function
///      produces a new ID rather than silently reusing an old one. `operationId` reverts with
///      `UnclassifiedOperation` for anything not in the matrix, so unknown operations fail closed.
library PauseMatrix {
    /// @notice Version of the pause matrix enforced by this build.
    uint16 internal constant PAUSE_MATRIX_VERSION = 1;

    /// @notice Canonical error raised when a scope-gated operation is blocked by a pause.
    /// @dev Single canonical pause error for every `SCOPE_*` gate. Modules MUST revert with this
    ///      (not `EnforcedPause`, not a legacy string) so pause semantics are uniform and
    ///      selector-stable across the V2 surface.
    error ProtocolPaused(bytes32 scope);

    /// @notice Registry key under which registry-resolved modules find their pause authority.
    /// @dev Byte-identical to `ModuleRegistryLib.MODULE_EMERGENCY_CONTROLS`.
    bytes32 internal constant MODULE_EMERGENCY_CONTROLS = keccak256("EMERGENCY_CONTROLS");

    /// @notice Domain separator mixed into every operation ID.
    /// @dev Prevents cross-domain collisions with unrelated keccak256(module, signature) digests.
    bytes32 internal constant OPERATION_ID_DOMAIN = keccak256("TruthBounty.V2.PauseMatrix.OperationId.v1");

    /// @notice Version of the operation ID derivation scheme.
    uint16 internal constant OPERATION_ID_VERSION = 1;

    // ─── Operation scopes (byte-identical to EmergencyControls scope constants) ─────────────

    /// @notice New claim creation and registration.
    bytes32 internal constant SCOPE_CLAIMS = keccak256("CLAIMS");
    /// @notice Evidence submission and adjudication.
    bytes32 internal constant SCOPE_EVIDENCE = keccak256("EVIDENCE");
    /// @notice Verifier staking, deposits, and new locks.
    bytes32 internal constant SCOPE_STAKING = keccak256("STAKING");
    /// @notice Verification attestations and aggregation of verification results.
    bytes32 internal constant SCOPE_VERIFICATION = keccak256("VERIFICATION");
    /// @notice Settlement, slashing, lock release, reward finalization, and pull-credit issuance.
    bytes32 internal constant SCOPE_SETTLEMENT = keccak256("SETTLEMENT");
    /// @notice Treasury movements.
    bytes32 internal constant SCOPE_TREASURY = keccak256("TREASURY");
    /// @notice Dispute initiation and resolution.
    bytes32 internal constant SCOPE_DISPUTES = keccak256("DISPUTES");
    /// @notice Module-level governance parameter and authority mutations (V2-SC-162).
    bytes32 internal constant SCOPE_GOVERNANCE = keccak256("GOVERNANCE");

    // ─── Pseudo-gates used by the mirror ────────────────────────────────────────────────────

    /// @notice Marks a value exit that freezes only at protocol SHUTDOWN.
    bytes32 internal constant EXIT_SHUTDOWN_ONLY = keccak256("EXIT_SHUTDOWN_ONLY");
    /// @notice Marks a governed-unpause operation that requires timelocked authority and full preconditions.
    bytes32 internal constant GOVERNED_UNPAUSE = keccak256("GOVERNED_UNPAUSE");
    /// @notice Placeholder for an unused gate slot.
    bytes32 internal constant NO_GATE = bytes32(0);

    /// @notice Canonical error raised when a token interaction fails (false return or revert).
    /// @dev Single canonical token-failure error for every token path. Modules MUST NOT surface
    ///      raw `SafeERC20FailedOperation`, `SafeERC20FailedOperation`-adjacent strings, or
    ///      legacy `"SafeERC20: ..."` strings; custody invariants are enforced by the caller.
    error TokenTransferFailed(address token, address to, uint256 amount);

    /// @notice Risk classification of an external operation.
    enum RiskClass {
        NEUTRAL,
        RISK_INCREASING,
        RISK_REDUCING,
        GOVERNED_UNPAUSE
    }

    /// @notice The (module, signature) pair is not part of the matrix.
    error UnclassifiedOperation(string moduleName, string signature);

    /// @notice Two distinct operations resolved to the same operation ID.
    /// @dev Reverts rather than silently aliasing; surfaced by the collision tests.
    error OperationIdCollision(bytes32 operationId, string moduleName, string signature);

    /// @notice The operation ID is not present in the matrix.
    error UnknownOperationId(bytes32 operationId);

    /// @notice Returns the canonical pause error for a scope gate.
    /// @dev Reverts with `ProtocolPaused(scope)` when `paused` is true. Callers MUST pass the
    ///      exact `SCOPE_*` gate returned by `classify`; passing a pseudo-gate or `NO_GATE` is a
    ///      programming error and reverts with `UnclassifiedOperation` to fail loudly.
    /// @param gate Scope gate to enforce.
    /// @param paused Whether the pause authority reports the scope as paused.
    function enforceScopeGate(bytes32 gate, bool paused) internal pure {
        if (!isScopeGate(gate)) revert UnclassifiedOperation("PauseMatrix", "enforceScopeGate");
        if (paused) revert ProtocolPaused(gate);
    }

    /// @notice Returns the canonical token-failure error.
    /// @dev Reverts with `TokenTransferFailed(token, to, amount)`. Callers MUST invoke this on any
    ///      false-return or reverting token interaction so token failures cannot corrupt custody
    ///      or double-pay.
    function revertTokenFailure(address token, address to, uint256 amount) internal pure {
        revert TokenTransferFailed(token, to, amount);
    }

    /// @notice Returns the classification and gates of a canonical V2 operation.
    /// @dev Reverts with `UnclassifiedOperation` for anything not in the matrix, so tests that walk
    ///      the matrix fail loudly when an operation is missing. `gateB` is `NO_GATE` for single-gate
    ///      operations; the gate set of an operation is `{gateA, gateB} \ {NO_GATE}`.
    /// @param moduleName Contract name of the module (e.g. "StakeVault").
    /// @param signature Source-level signature (e.g. "withdraw(address,uint256)").
    /// @return risk Risk class.
    /// @return gateA First gate (`SCOPE_*`, `EXIT_SHUTDOWN_ONLY`, or `NO_GATE`).
    /// @return gateB Second gate (`SCOPE_*` or `NO_GATE`).
    function classify(string memory moduleName, string memory signature)
        internal
        pure
        returns (RiskClass risk, bytes32 gateA, bytes32 gateB)
    {
        bytes32 k = _key(moduleName, signature);

        // Pause precedence is deterministic: `gateA` is evaluated before `gateB`. For operations
        // with two scope gates (e.g. `Aggregation.finalizeAggregation`), `gateA` MUST be checked
        // first so the reported `ProtocolPaused(scope)` is stable across runs.

        // ─── StakeVault ───────────────────────────────────────────────────────────────────
        if (k == _key("StakeVault", "depositStake(uint256,uint256)")) return (RiskClass.RISK_INCREASING, SCOPE_STAKING, NO_GATE);
        if (k == _key("StakeVault", "deposit(address,uint256)")) return (RiskClass.RISK_INCREASING, SCOPE_STAKING, NO_GATE);
        if (k == _key("StakeVault", "lock(address,address,uint256,uint256,IV2Types.LockCategory,uint256)")) return (RiskClass.RISK_INCREASING, SCOPE_STAKING, NO_GATE);
        if (k == _key("StakeVault", "releaseStake(uint256,address,uint256)")) return (RiskClass.RISK_INCREASING, SCOPE_SETTLEMENT, NO_GATE);
        if (k == _key("StakeVault", "slashStake(uint256,address,uint256,bytes32)")) return (RiskClass.RISK_INCREASING, SCOPE_SETTLEMENT, NO_GATE);
        if (k == _key("StakeVault", "unlock(address,address,uint256,uint256,IV2Types.LockCategory,uint256)")) return (RiskClass.RISK_INCREASING, SCOPE_SETTLEMENT, NO_GATE);
        if (k == _key("StakeVault", "allocateLocked(address,address,uint256,uint256,IV2Types.LockCategory,uint256,bytes32)")) return (RiskClass.RISK_INCREASING, SCOPE_SETTLEMENT, NO_GATE);
        if (k == _key("StakeVault", "settleConclusive(address,address,uint256,uint256,uint256,uint256)")) return (RiskClass.RISK_INCREASING, SCOPE_SETTLEMENT, NO_GATE);
        if (k == _key("StakeVault", "refundInconclusive(address,address,uint256,uint256,uint256)")) return (RiskClass.RISK_INCREASING, SCOPE_SETTLEMENT, NO_GATE);
        if (k == _key("StakeVault", "carryForwardAppeal(address,address,uint256,uint256,uint256,uint256)")) return (RiskClass.RISK_INCREASING, SCOPE_SETTLEMENT, NO_GATE);
        if (k == _key("StakeVault", "rolloverRound(address,address,uint256,uint256,uint256,uint256)")) return (RiskClass.RISK_INCREASING, SCOPE_SETTLEMENT, NO_GATE);
        if (k == _key("StakeVault", "finalUnlock(address,address,uint256,uint256,uint256)")) return (RiskClass.RISK_INCREASING, SCOPE_SETTLEMENT, NO_GATE);
        if (k == _key("StakeVault", "setMinStakeAmount(uint256)")) return (RiskClass.RISK_INCREASING, SCOPE_GOVERNANCE, NO_GATE);
        if (k == _key("StakeVault", "setSupportedAsset(address,bool)")) return (RiskClass.RISK_INCREASING, SCOPE_GOVERNANCE, NO_GATE);
        if (k == _key("StakeVault", "setLockMutator(address,bool)")) return (RiskClass.RISK_INCREASING, SCOPE_GOVERNANCE, NO_GATE);
        if (k == _key("StakeVault", "withdraw(address,uint256)")) return (RiskClass.RISK_REDUCING, EXIT_SHUTDOWN_ONLY, NO_GATE);

        // ─── Claims ───────────────────────────────────────────────────────────────────────
        if (k == _key("Claims", "createClaim(bytes32,uint256,bytes)")) return (RiskClass.RISK_INCREASING, SCOPE_CLAIMS, NO_GATE);
        if (k == _key("Claims", "finalizeClaim(uint256,IV2Types.ClaimStatus)")) return (RiskClass.RISK_INCREASING, SCOPE_SETTLEMENT, NO_GATE);
        if (k == _key("Claims", "setAntiGriefParams(uint256,uint256,uint256,uint64,uint256,address)")) return (RiskClass.RISK_INCREASING, SCOPE_GOVERNANCE, NO_GATE);
        if (k == _key("Claims", "cancelClaim(uint256)")) return (RiskClass.RISK_REDUCING, EXIT_SHUTDOWN_ONLY, SCOPE_SETTLEMENT);
        if (k == _key("Claims", "setPauseAuthority(address)")) return (RiskClass.NEUTRAL, NO_GATE, NO_GATE);

        // ─── EvidenceRegistry ─────────────────────────────────────────────────────────────
        if (k == _key("EvidenceRegistry", "submitEvidence(uint256,bytes32,bytes)")) return (RiskClass.RISK_INCREASING, SCOPE_EVIDENCE, NO_GATE);
        if (k == _key("EvidenceRegistry", "commitEvidence(uint256,bytes32,bytes32,uint256)")) return (RiskClass.RISK_INCREASING, SCOPE_EVIDENCE, NO_GATE);
        if (k == _key("EvidenceRegistry", "setEvidenceStatus(uint256,IV2Types.EvidenceStatus)")) return (RiskClass.RISK_INCREASING, SCOPE_EVIDENCE, NO_GATE);
        if (k == _key("EvidenceRegistry", "pause()")) return (RiskClass.RISK_REDUCING, NO_GATE, NO_GATE);
        if (k == _key("EvidenceRegistry", "unpause()")) return (RiskClass.GOVERNED_UNPAUSE, GOVERNED_UNPAUSE, NO_GATE);
        if (k == _key("EvidenceRegistry", "governedUnpause(bytes32,bytes32,address,bytes32,bytes32)")) return (RiskClass.GOVERNED_UNPAUSE, GOVERNED_UNPAUSE, NO_GATE);
        if (k == _key("EvidenceRegistry", "guardianUnpause()")) return (RiskClass.GOVERNED_UNPAUSE, GOVERNED_UNPAUSE, NO_GATE);
        if (k == _key("EvidenceRegistry", "setPauseAuthority(address)")) return (RiskClass.NEUTRAL, NO_GATE, NO_GATE);

        // ─── FinalRewardAllocator ─────────────────────────────────────────────────────────
        if (k == _key("FinalRewardAllocator", "fund(address,uint256,bytes32)")) return (RiskClass.RISK_INCREASING, SCOPE_SETTLEMENT, NO_GATE);
        if (k == _key("FinalRewardAllocator", "finalizeRewards(bytes32,address,FinalOutcome,Allocation[])")) return (RiskClass.RISK_INCREASING, SCOPE_SETTLEMENT, NO_GATE);
        if (k == _key("FinalRewardAllocator", "claim(address,uint256)")) return (RiskClass.RISK_REDUCING, EXIT_SHUTDOWN_ONLY, NO_GATE);

        // ─── Aggregation ──────────────────────────────────────────────────────────────────
        if (k == _key("Aggregation", "finalizeAggregation(uint256)")) return (RiskClass.RISK_INCREASING, SCOPE_VERIFICATION, SCOPE_SETTLEMENT);

        // ─── PullSettlementLedger ─────────────────────────────────────────────────────────
        if (k == _key("PullSettlementLedger", "credit(address,uint256,bytes32)")) return (RiskClass.RISK_INCREASING, SCOPE_SETTLEMENT, NO_GATE);
        if (k == _key("PullSettlementLedger", "creditBatch(address[],uint256[],bytes32)")) return (RiskClass.RISK_INCREASING, SCOPE_SETTLEMENT, NO_GATE);
        if (k == _key("PullSettlementLedger", "withdraw(uint256)")) return (RiskClass.RISK_REDUCING, EXIT_SHUTDOWN_ONLY, NO_GATE);
        if (k == _key("PullSettlementLedger", "withdrawFromRef(bytes32,uint256)")) return (RiskClass.RISK_REDUCING, EXIT_SHUTDOWN_ONLY, NO_GATE);
        if (k == _key("PullSettlementLedger", "setPauseAuthority(address)")) return (RiskClass.NEUTRAL, NO_GATE, NO_GATE);
        if (k == _key("PullSettlementLedger", "unpause()")) return (RiskClass.GOVERNED_UNPAUSE, GOVERNED_UNPAUSE, NO_GATE);
        if (k == _key("PullSettlementLedger", "governedUnpause(bytes32,bytes32,address,bytes32,bytes32)")) return (RiskClass.GOVERNED_UNPAUSE, GOVERNED_UNPAUSE, NO_GATE);
        if (k == _key("PullSettlementLedger", "guardianUnpause()")) return (RiskClass.GOVERNED_UNPAUSE, GOVERNED_UNPAUSE, NO_GATE);

        // ─── SignatureNonces ──────────────────────────────────────────────────────────────
        if (k == _key("SignatureNonces", "cancelNonce(uint256)")) return (RiskClass.RISK_REDUCING, NO_GATE, NO_GATE);

        revert UnclassifiedOperation(moduleName, signature);
    }

    /// @notice Returns the canonical, stable operation ID for a classified operation.
    /// @dev The ID is `keccak256(OPERATION_ID_DOMAIN, OPERATION_ID_VERSION, moduleName, signature)`.
    ///      It is deterministic, namespaced by module, and domain-separated so that identical
    ///      signatures on different modules cannot alias. Reverts with `UnclassifiedOperation` for
    ///      anything not in the matrix so unknown operations fail closed.
    /// @param moduleName Contract name of the module (e.g. "StakeVault").
    /// @param signature Source-level signature (e.g. "withdraw(address,uint256)").
    /// @return operationId_ Stable operation identifier.
    function operationId(string memory moduleName, string memory signature)
        internal
        pure
        returns (bytes32 operationId_)
    {
        // Fail closed: unknown operations must not receive an ID.
        classify(moduleName, signature);
        return _deriveOperationId(moduleName, signature);
    }

    /// @notice Returns the operation ID for a known ID, reverting if unknown.
    /// @dev Used by consumers that only hold an ID (e.g. frontend/API handoffs) to fail closed.
    /// @param id Operation ID to validate.
    /// @return moduleName Module name of the operation.
    /// @return signature Source-level signature of the operation.
    function resolveOperationId(bytes32 id)
        internal
        pure
        returns (string memory moduleName, string memory signature)
    {
        (moduleName, signature) = _lookupOperationId(id);
        if (bytes(moduleName).length == 0) revert UnknownOperationId(id);
    }

    /// @notice Returns the canonical operation matrix in deterministic source order.
    function operationMatrix() internal pure returns (bytes32[] memory ids, string[] memory names) {
        ids = new bytes32[](42);
        names = new string[](42);
        ids[0] = _deriveOperationId("StakeVault", "depositStake(uint256,uint256)");
        names[0] = "StakeVault.depositStake(uint256,uint256)";
        ids[1] = _deriveOperationId("StakeVault", "deposit(address,uint256)");
        names[1] = "StakeVault.deposit(address,uint256)";
        ids[2] = _deriveOperationId("StakeVault", "lock(address,address,uint256,uint256,IV2Types.LockCategory,uint256)");
        names[2] = "StakeVault.lock(address,address,uint256,uint256,IV2Types.LockCategory,uint256)";
        ids[3] = _deriveOperationId("StakeVault", "releaseStake(uint256,address,uint256)");
        names[3] = "StakeVault.releaseStake(uint256,address,uint256)";
        ids[4] = _deriveOperationId("StakeVault", "slashStake(uint256,address,uint256,bytes32)");
        names[4] = "StakeVault.slashStake(uint256,address,uint256,bytes32)";
        ids[5] = _deriveOperationId("StakeVault", "unlock(address,address,uint256,uint256,IV2Types.LockCategory,uint256)");
        names[5] = "StakeVault.unlock(address,address,uint256,uint256,IV2Types.LockCategory,uint256)";
        ids[6] = _deriveOperationId("StakeVault", "allocateLocked(address,address,uint256,uint256,IV2Types.LockCategory,uint256,bytes32)");
        names[6] = "StakeVault.allocateLocked(address,address,uint256,uint256,IV2Types.LockCategory,uint256,bytes32)";
        ids[7] = _deriveOperationId("StakeVault", "settleConclusive(address,address,uint256,uint256,uint256,uint256)");
        names[7] = "StakeVault.settleConclusive(address,address,uint256,uint256,uint256,uint256)";
        ids[8] = _deriveOperationId("StakeVault", "refundInconclusive(address,address,uint256,uint256,uint256)");
        names[8] = "StakeVault.refundInconclusive(address,address,uint256,uint256,uint256)";
        ids[9] = _deriveOperationId("StakeVault", "carryForwardAppeal(address,address,uint256,uint256,uint256,uint256)");
        names[9] = "StakeVault.carryForwardAppeal(address,address,uint256,uint256,uint256,uint256)";
        ids[10] = _deriveOperationId("StakeVault", "rolloverRound(address,address,uint256,uint256,uint256,uint256)");
        names[10] = "StakeVault.rolloverRound(address,address,uint256,uint256,uint256,uint256)";
        ids[11] = _deriveOperationId("StakeVault", "finalUnlock(address,address,uint256,uint256,uint256)");
        names[11] = "StakeVault.finalUnlock(address,address,uint256,uint256,uint256)";
        ids[12] = _deriveOperationId("StakeVault", "setMinStakeAmount(uint256)");
        names[12] = "StakeVault.setMinStakeAmount(uint256)";
        ids[13] = _deriveOperationId("StakeVault", "setSupportedAsset(address,bool)");
        names[13] = "StakeVault.setSupportedAsset(address,bool)";
        ids[14] = _deriveOperationId("StakeVault", "setLockMutator(address,bool)");
        names[14] = "StakeVault.setLockMutator(address,bool)";
        ids[15] = _deriveOperationId("StakeVault", "withdraw(address,uint256)");
        names[15] = "StakeVault.withdraw(address,uint256)";
        ids[16] = _deriveOperationId("Claims", "createClaim(bytes32,uint256,bytes)");
        names[16] = "Claims.createClaim(bytes32,uint256,bytes)";
        ids[17] = _deriveOperationId("Claims", "finalizeClaim(uint256,IV2Types.ClaimStatus)");
        names[17] = "Claims.finalizeClaim(uint256,IV2Types.ClaimStatus)";
        ids[18] = _deriveOperationId("Claims", "setAntiGriefParams(uint256,uint256,uint256,uint64,uint256,address)");
        names[18] = "Claims.setAntiGriefParams(uint256,uint256,uint256,uint64,uint256,address)";
        ids[19] = _deriveOperationId("Claims", "cancelClaim(uint256)");
        names[19] = "Claims.cancelClaim(uint256)";
        ids[20] = _deriveOperationId("Claims", "setPauseAuthority(address)");
        names[20] = "Claims.setPauseAuthority(address)";
        ids[21] = _deriveOperationId("EvidenceRegistry", "submitEvidence(uint256,bytes32,bytes)");
        names[21] = "EvidenceRegistry.submitEvidence(uint256,bytes32,bytes)";
        ids[22] = _deriveOperationId("EvidenceRegistry", "commitEvidence(uint256,bytes32,bytes32,uint256)");
        names[22] = "EvidenceRegistry.commitEvidence(uint256,bytes32,bytes32,uint256)";
        ids[23] = _deriveOperationId("EvidenceRegistry", "setEvidenceStatus(uint256,IV2Types.EvidenceStatus)");
        names[23] = "EvidenceRegistry.setEvidenceStatus(uint256,IV2Types.EvidenceStatus)";
        ids[24] = _deriveOperationId("EvidenceRegistry", "pause()");
        names[24] = "EvidenceRegistry.pause()";
        ids[25] = _deriveOperationId("EvidenceRegistry", "unpause()");
        names[25] = "EvidenceRegistry.unpause()";
        ids[26] = _deriveOperationId("EvidenceRegistry", "governedUnpause(bytes32,bytes32,address,bytes32,bytes32)");
        names[26] = "EvidenceRegistry.governedUnpause(bytes32,bytes32,address,bytes32,bytes32)";
        ids[27] = _deriveOperationId("EvidenceRegistry", "guardianUnpause()");
        names[27] = "EvidenceRegistry.guardianUnpause()";
        ids[28] = _deriveOperationId("EvidenceRegistry", "setPauseAuthority(address)");
        names[28] = "EvidenceRegistry.setPauseAuthority(address)";
        ids[29] = _deriveOperationId("FinalRewardAllocator", "fund(address,uint256,bytes32)");
        names[29] = "FinalRewardAllocator.fund(address,uint256,bytes32)";
        ids[30] = _deriveOperationId("FinalRewardAllocator", "finalizeRewards(bytes32,address,FinalOutcome,Allocation[])");
        names[30] = "FinalRewardAllocator.finalizeRewards(bytes32,address,FinalOutcome,Allocation[])";
        ids[31] = _deriveOperationId("FinalRewardAllocator", "claim(address,uint256)");
        names[31] = "FinalRewardAllocator.claim(address,uint256)";
        ids[32] = _deriveOperationId("Aggregation", "finalizeAggregation(uint256)");
        names[32] = "Aggregation.finalizeAggregation(uint256)";
        ids[33] = _deriveOperationId("PullSettlementLedger", "credit(address,uint256,bytes32)");
        names[33] = "PullSettlementLedger.credit(address,uint256,bytes32)";
        ids[34] = _deriveOperationId("PullSettlementLedger", "creditBatch(address[],uint256[],bytes32)");
        names[34] = "PullSettlementLedger.creditBatch(address[],uint256[],bytes32)";
        ids[35] = _deriveOperationId("PullSettlementLedger", "withdraw(uint256)");
        names[35] = "PullSettlementLedger.withdraw(uint256)";
        ids[36] = _deriveOperationId("PullSettlementLedger", "withdrawFromRef(bytes32,uint256)");
        names[36] = "PullSettlementLedger.withdrawFromRef(bytes32,uint256)";
        ids[37] = _deriveOperationId("PullSettlementLedger", "setPauseAuthority(address)");
        names[37] = "PullSettlementLedger.setPauseAuthority(address)";
        ids[38] = _deriveOperationId("PullSettlementLedger", "unpause()");
        names[38] = "PullSettlementLedger.unpause()";
        ids[39] = _deriveOperationId("PullSettlementLedger", "governedUnpause(bytes32,bytes32,address,bytes32,bytes32)");
        names[39] = "PullSettlementLedger.governedUnpause(bytes32,bytes32,address,bytes32,bytes32)";
        ids[40] = _deriveOperationId("PullSettlementLedger", "guardianUnpause()");
        names[40] = "PullSettlementLedger.guardianUnpause()";
        ids[41] = _deriveOperationId("SignatureNonces", "cancelNonce(uint256)");
        names[41] = "SignatureNonces.cancelNonce(uint256)";
    }

    /// @notice Resolves a selector only when it identifies exactly one module-scoped operation.
    /// @dev Duplicate selectors across modules return zero; callers must not guess the module.
    function operationIdForSelector(bytes4 selector) internal pure returns (bytes32 candidate) {
        if (selector == bytes4(keccak256(bytes("depositStake(uint256,uint256)")))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "depositStake(uint256,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("deposit(address,uint256)")))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "deposit(address,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("lock(address,address,uint256,uint256,IV2Types.LockCategory,uint256)")))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "lock(address,address,uint256,uint256,IV2Types.LockCategory,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("releaseStake(uint256,address,uint256)")))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "releaseStake(uint256,address,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("slashStake(uint256,address,uint256,bytes32)")))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "slashStake(uint256,address,uint256,bytes32)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("unlock(address,address,uint256,uint256,IV2Types.LockCategory,uint256)")))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "unlock(address,address,uint256,uint256,IV2Types.LockCategory,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("allocateLocked(address,address,uint256,uint256,IV2Types.LockCategory,uint256,bytes32)")))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "allocateLocked(address,address,uint256,uint256,IV2Types.LockCategory,uint256,bytes32)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("settleConclusive(address,address,uint256,uint256,uint256,uint256)")))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "settleConclusive(address,address,uint256,uint256,uint256,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("refundInconclusive(address,address,uint256,uint256,uint256)")))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "refundInconclusive(address,address,uint256,uint256,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("carryForwardAppeal(address,address,uint256,uint256,uint256,uint256)")))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "carryForwardAppeal(address,address,uint256,uint256,uint256,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("rolloverRound(address,address,uint256,uint256,uint256,uint256)")))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "rolloverRound(address,address,uint256,uint256,uint256,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("finalUnlock(address,address,uint256,uint256,uint256)")))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "finalUnlock(address,address,uint256,uint256,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("setMinStakeAmount(uint256)")))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "setMinStakeAmount(uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("setSupportedAsset(address,bool)")))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "setSupportedAsset(address,bool)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("setLockMutator(address,bool)")))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "setLockMutator(address,bool)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("withdraw(address,uint256)")))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "withdraw(address,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("createClaim(bytes32,uint256,bytes)")))) {
            bytes32 nextId = _deriveOperationId("Claims", "createClaim(bytes32,uint256,bytes)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("finalizeClaim(uint256,IV2Types.ClaimStatus)")))) {
            bytes32 nextId = _deriveOperationId("Claims", "finalizeClaim(uint256,IV2Types.ClaimStatus)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("setAntiGriefParams(uint256,uint256,uint256,uint64,uint256,address)")))) {
            bytes32 nextId = _deriveOperationId("Claims", "setAntiGriefParams(uint256,uint256,uint256,uint64,uint256,address)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("cancelClaim(uint256)")))) {
            bytes32 nextId = _deriveOperationId("Claims", "cancelClaim(uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("setPauseAuthority(address)")))) {
            bytes32 nextId = _deriveOperationId("Claims", "setPauseAuthority(address)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("submitEvidence(uint256,bytes32,bytes)")))) {
            bytes32 nextId = _deriveOperationId("EvidenceRegistry", "submitEvidence(uint256,bytes32,bytes)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("commitEvidence(uint256,bytes32,bytes32,uint256)")))) {
            bytes32 nextId = _deriveOperationId("EvidenceRegistry", "commitEvidence(uint256,bytes32,bytes32,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("setEvidenceStatus(uint256,IV2Types.EvidenceStatus)")))) {
            bytes32 nextId = _deriveOperationId("EvidenceRegistry", "setEvidenceStatus(uint256,IV2Types.EvidenceStatus)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("pause()")))) {
            bytes32 nextId = _deriveOperationId("EvidenceRegistry", "pause()");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("unpause()")))) {
            bytes32 nextId = _deriveOperationId("EvidenceRegistry", "unpause()");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("governedUnpause(bytes32,bytes32,address,bytes32,bytes32)")))) {
            bytes32 nextId = _deriveOperationId("EvidenceRegistry", "governedUnpause(bytes32,bytes32,address,bytes32,bytes32)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("guardianUnpause()")))) {
            bytes32 nextId = _deriveOperationId("EvidenceRegistry", "guardianUnpause()");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("setPauseAuthority(address)")))) {
            bytes32 nextId = _deriveOperationId("EvidenceRegistry", "setPauseAuthority(address)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("fund(address,uint256,bytes32)")))) {
            bytes32 nextId = _deriveOperationId("FinalRewardAllocator", "fund(address,uint256,bytes32)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("finalizeRewards(bytes32,address,FinalOutcome,Allocation[])")))) {
            bytes32 nextId = _deriveOperationId("FinalRewardAllocator", "finalizeRewards(bytes32,address,FinalOutcome,Allocation[])");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("claim(address,uint256)")))) {
            bytes32 nextId = _deriveOperationId("FinalRewardAllocator", "claim(address,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("finalizeAggregation(uint256)")))) {
            bytes32 nextId = _deriveOperationId("Aggregation", "finalizeAggregation(uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("credit(address,uint256,bytes32)")))) {
            bytes32 nextId = _deriveOperationId("PullSettlementLedger", "credit(address,uint256,bytes32)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("creditBatch(address[],uint256[],bytes32)")))) {
            bytes32 nextId = _deriveOperationId("PullSettlementLedger", "creditBatch(address[],uint256[],bytes32)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("withdraw(uint256)")))) {
            bytes32 nextId = _deriveOperationId("PullSettlementLedger", "withdraw(uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("withdrawFromRef(bytes32,uint256)")))) {
            bytes32 nextId = _deriveOperationId("PullSettlementLedger", "withdrawFromRef(bytes32,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("setPauseAuthority(address)")))) {
            bytes32 nextId = _deriveOperationId("PullSettlementLedger", "setPauseAuthority(address)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("unpause()")))) {
            bytes32 nextId = _deriveOperationId("PullSettlementLedger", "unpause()");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("governedUnpause(bytes32,bytes32,address,bytes32,bytes32)")))) {
            bytes32 nextId = _deriveOperationId("PullSettlementLedger", "governedUnpause(bytes32,bytes32,address,bytes32,bytes32)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("guardianUnpause()")))) {
            bytes32 nextId = _deriveOperationId("PullSettlementLedger", "guardianUnpause()");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (selector == bytes4(keccak256(bytes("cancelNonce(uint256)")))) {
            bytes32 nextId = _deriveOperationId("SignatureNonces", "cancelNonce(uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
    }

    /// @notice Resolves a source-level signature only when it is unique across modules.
    function operationIdForName(string memory signature) internal pure returns (bytes32 candidate) {
        if (keccak256(bytes(signature)) == keccak256(bytes("depositStake(uint256,uint256)"))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "depositStake(uint256,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("deposit(address,uint256)"))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "deposit(address,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("lock(address,address,uint256,uint256,IV2Types.LockCategory,uint256)"))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "lock(address,address,uint256,uint256,IV2Types.LockCategory,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("releaseStake(uint256,address,uint256)"))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "releaseStake(uint256,address,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("slashStake(uint256,address,uint256,bytes32)"))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "slashStake(uint256,address,uint256,bytes32)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("unlock(address,address,uint256,uint256,IV2Types.LockCategory,uint256)"))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "unlock(address,address,uint256,uint256,IV2Types.LockCategory,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("allocateLocked(address,address,uint256,uint256,IV2Types.LockCategory,uint256,bytes32)"))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "allocateLocked(address,address,uint256,uint256,IV2Types.LockCategory,uint256,bytes32)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("settleConclusive(address,address,uint256,uint256,uint256,uint256)"))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "settleConclusive(address,address,uint256,uint256,uint256,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("refundInconclusive(address,address,uint256,uint256,uint256)"))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "refundInconclusive(address,address,uint256,uint256,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("carryForwardAppeal(address,address,uint256,uint256,uint256,uint256)"))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "carryForwardAppeal(address,address,uint256,uint256,uint256,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("rolloverRound(address,address,uint256,uint256,uint256,uint256)"))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "rolloverRound(address,address,uint256,uint256,uint256,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("finalUnlock(address,address,uint256,uint256,uint256)"))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "finalUnlock(address,address,uint256,uint256,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("setMinStakeAmount(uint256)"))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "setMinStakeAmount(uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("setSupportedAsset(address,bool)"))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "setSupportedAsset(address,bool)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("setLockMutator(address,bool)"))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "setLockMutator(address,bool)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("withdraw(address,uint256)"))) {
            bytes32 nextId = _deriveOperationId("StakeVault", "withdraw(address,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("createClaim(bytes32,uint256,bytes)"))) {
            bytes32 nextId = _deriveOperationId("Claims", "createClaim(bytes32,uint256,bytes)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("finalizeClaim(uint256,IV2Types.ClaimStatus)"))) {
            bytes32 nextId = _deriveOperationId("Claims", "finalizeClaim(uint256,IV2Types.ClaimStatus)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("setAntiGriefParams(uint256,uint256,uint256,uint64,uint256,address)"))) {
            bytes32 nextId = _deriveOperationId("Claims", "setAntiGriefParams(uint256,uint256,uint256,uint64,uint256,address)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("cancelClaim(uint256)"))) {
            bytes32 nextId = _deriveOperationId("Claims", "cancelClaim(uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("setPauseAuthority(address)"))) {
            bytes32 nextId = _deriveOperationId("Claims", "setPauseAuthority(address)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("setPauseAuthority(address)"))) {
            bytes32 nextId = _deriveOperationId("EvidenceRegistry", "setPauseAuthority(address)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("setPauseAuthority(address)"))) {
            bytes32 nextId = _deriveOperationId("PullSettlementLedger", "setPauseAuthority(address)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("submitEvidence(uint256,bytes32,bytes)"))) {
            bytes32 nextId = _deriveOperationId("EvidenceRegistry", "submitEvidence(uint256,bytes32,bytes)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("commitEvidence(uint256,bytes32,bytes32,uint256)"))) {
            bytes32 nextId = _deriveOperationId("EvidenceRegistry", "commitEvidence(uint256,bytes32,bytes32,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("setEvidenceStatus(uint256,IV2Types.EvidenceStatus)"))) {
            bytes32 nextId = _deriveOperationId("EvidenceRegistry", "setEvidenceStatus(uint256,IV2Types.EvidenceStatus)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("pause()"))) {
            bytes32 nextId = _deriveOperationId("EvidenceRegistry", "pause()");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("unpause()"))) {
            bytes32 nextId = _deriveOperationId("EvidenceRegistry", "unpause()");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("unpause()"))) {
            bytes32 nextId = _deriveOperationId("PullSettlementLedger", "unpause()");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("governedUnpause(bytes32,bytes32,address,bytes32,bytes32)"))) {
            bytes32 nextId = _deriveOperationId("EvidenceRegistry", "governedUnpause(bytes32,bytes32,address,bytes32,bytes32)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("governedUnpause(bytes32,bytes32,address,bytes32,bytes32)"))) {
            bytes32 nextId = _deriveOperationId("PullSettlementLedger", "governedUnpause(bytes32,bytes32,address,bytes32,bytes32)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("guardianUnpause()"))) {
            bytes32 nextId = _deriveOperationId("EvidenceRegistry", "guardianUnpause()");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("guardianUnpause()"))) {
            bytes32 nextId = _deriveOperationId("PullSettlementLedger", "guardianUnpause()");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("fund(address,uint256,bytes32)"))) {
            bytes32 nextId = _deriveOperationId("FinalRewardAllocator", "fund(address,uint256,bytes32)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("finalizeRewards(bytes32,address,FinalOutcome,Allocation[])"))) {
            bytes32 nextId = _deriveOperationId("FinalRewardAllocator", "finalizeRewards(bytes32,address,FinalOutcome,Allocation[])");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("claim(address,uint256)"))) {
            bytes32 nextId = _deriveOperationId("FinalRewardAllocator", "claim(address,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("finalizeAggregation(uint256)"))) {
            bytes32 nextId = _deriveOperationId("Aggregation", "finalizeAggregation(uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("credit(address,uint256,bytes32)"))) {
            bytes32 nextId = _deriveOperationId("PullSettlementLedger", "credit(address,uint256,bytes32)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("creditBatch(address[],uint256[],bytes32)"))) {
            bytes32 nextId = _deriveOperationId("PullSettlementLedger", "creditBatch(address[],uint256[],bytes32)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("withdraw(uint256)"))) {
            bytes32 nextId = _deriveOperationId("PullSettlementLedger", "withdraw(uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("withdrawFromRef(bytes32,uint256)"))) {
            bytes32 nextId = _deriveOperationId("PullSettlementLedger", "withdrawFromRef(bytes32,uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
        if (keccak256(bytes(signature)) == keccak256(bytes("cancelNonce(uint256)"))) {
            bytes32 nextId = _deriveOperationId("SignatureNonces", "cancelNonce(uint256)");
            if (candidate != bytes32(0) && candidate != nextId) return bytes32(0);
            candidate = nextId;
        }
    }

    /// @notice Returns a stable, domain-separated identifier for a recognized pause scope.
    function operationIdForScope(bytes32 scope) internal pure returns (bytes32) {
        if (!isScopeGate(scope)) return bytes32(0);
        return keccak256(abi.encode(OPERATION_ID_DOMAIN, OPERATION_ID_VERSION, "SCOPE", scope));
    }

    /// @notice Nested scopes are not declared in the current canonical matrix.
    function operationIdForNestedScope(bytes32) internal pure returns (bytes32) {
        return bytes32(0);
    }

    /// @notice True when `gate` is an operation scope (as opposed to a pseudo-gate or `NO_GATE`).
    /// @param gate Gate identifier returned by `classify`.
    /// @return isScope Whether the gate is one of the `SCOPE_*` constants.
    function isScopeGate(bytes32 gate) internal pure returns (bool isScope) {
        return gate == SCOPE_CLAIMS || gate == SCOPE_EVIDENCE || gate == SCOPE_STAKING || gate == SCOPE_VERIFICATION
            || gate == SCOPE_SETTLEMENT || gate == SCOPE_TREASURY || gate == SCOPE_DISPUTES || gate == SCOPE_GOVERNANCE;
    }

    /// @notice True when `gate` marks a governed-unpause operation requiring full preconditions.
    /// @param gate Gate identifier returned by `classify`.
    /// @return isGovernedUnpause Whether the gate is the `GOVERNED_UNPAUSE` pseudo-gate.
    function isGovernedUnpauseGate(bytes32 gate) internal pure returns (bool isGovernedUnpause) {
        return gate == GOVERNED_UNPAUSE;
    }

    function _deriveOperationId(string memory moduleName, string memory signature) private pure returns (bytes32) {
        return keccak256(abi.encode(OPERATION_ID_DOMAIN, OPERATION_ID_VERSION, moduleName, signature));
    }

    function _lookupOperationId(bytes32 id) private pure returns (string memory moduleName, string memory signature) {
        if (id == _deriveOperationId("StakeVault", "depositStake(uint256,uint256)")) return ("StakeVault", "depositStake(uint256,uint256)");
        if (id == _deriveOperationId("StakeVault", "deposit(address,uint256)")) return ("StakeVault", "deposit(address,uint256)");
        if (id == _deriveOperationId("StakeVault", "lock(address,address,uint256,uint256,IV2Types.LockCategory,uint256)")) return ("StakeVault", "lock(address,address,uint256,uint256,IV2Types.LockCategory,uint256)");
        if (id == _deriveOperationId("StakeVault", "releaseStake(uint256,address,uint256)")) return ("StakeVault", "releaseStake(uint256,address,uint256)");
        if (id == _deriveOperationId("StakeVault", "slashStake(uint256,address,uint256,bytes32)")) return ("StakeVault", "slashStake(uint256,address,uint256,bytes32)");
        if (id == _deriveOperationId("StakeVault", "unlock(address,address,uint256,uint256,IV2Types.LockCategory,uint256)")) return ("StakeVault", "unlock(address,address,uint256,uint256,IV2Types.LockCategory,uint256)");
        if (id == _deriveOperationId("StakeVault", "allocateLocked(address,address,uint256,uint256,IV2Types.LockCategory,uint256,bytes32)")) return ("StakeVault", "allocateLocked(address,address,uint256,uint256,IV2Types.LockCategory,uint256,bytes32)");
        if (id == _deriveOperationId("StakeVault", "settleConclusive(address,address,uint256,uint256,uint256,uint256)")) return ("StakeVault", "settleConclusive(address,address,uint256,uint256,uint256,uint256)");
        if (id == _deriveOperationId("StakeVault", "refundInconclusive(address,address,uint256,uint256,uint256)")) return ("StakeVault", "refundInconclusive(address,address,uint256,uint256,uint256)");
        if (id == _deriveOperationId("StakeVault", "carryForwardAppeal(address,address,uint256,uint256,uint256,uint256)")) return ("StakeVault", "carryForwardAppeal(address,address,uint256,uint256,uint256,uint256)");
        if (id == _deriveOperationId("StakeVault", "rolloverRound(address,address,uint256,uint256,uint256,uint256)")) return ("StakeVault", "rolloverRound(address,address,uint256,uint256,uint256,uint256)");
        if (id == _deriveOperationId("StakeVault", "finalUnlock(address,address,uint256,uint256,uint256)")) return ("StakeVault", "finalUnlock(address,address,uint256,uint256,uint256)");
        if (id == _deriveOperationId("StakeVault", "setMinStakeAmount(uint256)")) return ("StakeVault", "setMinStakeAmount(uint256)");
        if (id == _deriveOperationId("StakeVault", "setSupportedAsset(address,bool)")) return ("StakeVault", "setSupportedAsset(address,bool)");
        if (id == _deriveOperationId("StakeVault", "setLockMutator(address,bool)")) return ("StakeVault", "setLockMutator(address,bool)");
        if (id == _deriveOperationId("StakeVault", "withdraw(address,uint256)")) return ("StakeVault", "withdraw(address,uint256)");
        if (id == _deriveOperationId("Claims", "createClaim(bytes32,uint256,bytes)")) return ("Claims", "createClaim(bytes32,uint256,bytes)");
        if (id == _deriveOperationId("Claims", "finalizeClaim(uint256,IV2Types.ClaimStatus)")) return ("Claims", "finalizeClaim(uint256,IV2Types.ClaimStatus)");
        if (id == _deriveOperationId("Claims", "setAntiGriefParams(uint256,uint256,uint256,uint64,uint256,address)")) return ("Claims", "setAntiGriefParams(uint256,uint256,uint256,uint64,uint256,address)");
        if (id == _deriveOperationId("Claims", "cancelClaim(uint256)")) return ("Claims", "cancelClaim(uint256)");
        if (id == _deriveOperationId("Claims", "setPauseAuthority(address)")) return ("Claims", "setPauseAuthority(address)");
        if (id == _deriveOperationId("EvidenceRegistry", "submitEvidence(uint256,bytes32,bytes)")) return ("EvidenceRegistry", "submitEvidence(uint256,bytes32,bytes)");
        if (id == _deriveOperationId("EvidenceRegistry", "commitEvidence(uint256,bytes32,bytes32,uint256)")) return ("EvidenceRegistry", "commitEvidence(uint256,bytes32,bytes32,uint256)");
        if (id == _deriveOperationId("EvidenceRegistry", "setEvidenceStatus(uint256,IV2Types.EvidenceStatus)")) return ("EvidenceRegistry", "setEvidenceStatus(uint256,IV2Types.EvidenceStatus)");
        if (id == _deriveOperationId("EvidenceRegistry", "pause()")) return ("EvidenceRegistry", "pause()");
        if (id == _deriveOperationId("EvidenceRegistry", "unpause()")) return ("EvidenceRegistry", "unpause()");
        if (id == _deriveOperationId("EvidenceRegistry", "governedUnpause(bytes32,bytes32,address,bytes32,bytes32)")) return ("EvidenceRegistry", "governedUnpause(bytes32,bytes32,address,bytes32,bytes32)");
        if (id == _deriveOperationId("EvidenceRegistry", "guardianUnpause()")) return ("EvidenceRegistry", "guardianUnpause()");
        if (id == _deriveOperationId("EvidenceRegistry", "setPauseAuthority(address)")) return ("EvidenceRegistry", "setPauseAuthority(address)");
        if (id == _deriveOperationId("FinalRewardAllocator", "fund(address,uint256,bytes32)")) return ("FinalRewardAllocator", "fund(address,uint256,bytes32)");
        if (id == _deriveOperationId("FinalRewardAllocator", "finalizeRewards(bytes32,address,FinalOutcome,Allocation[])")) return ("FinalRewardAllocator", "finalizeRewards(bytes32,address,FinalOutcome,Allocation[])");
        if (id == _deriveOperationId("FinalRewardAllocator", "claim(address,uint256)")) return ("FinalRewardAllocator", "claim(address,uint256)");
        if (id == _deriveOperationId("Aggregation", "finalizeAggregation(uint256)")) return ("Aggregation", "finalizeAggregation(uint256)");
        if (id == _deriveOperationId("PullSettlementLedger", "credit(address,uint256,bytes32)")) return ("PullSettlementLedger", "credit(address,uint256,bytes32)");
        if (id == _deriveOperationId("PullSettlementLedger", "creditBatch(address[],uint256[],bytes32)")) return ("PullSettlementLedger", "creditBatch(address[],uint256[],bytes32)");
        if (id == _deriveOperationId("PullSettlementLedger", "withdraw(uint256)")) return ("PullSettlementLedger", "withdraw(uint256)");
        if (id == _deriveOperationId("PullSettlementLedger", "withdrawFromRef(bytes32,uint256)")) return ("PullSettlementLedger", "withdrawFromRef(bytes32,uint256)");
        if (id == _deriveOperationId("PullSettlementLedger", "setPauseAuthority(address)")) return ("PullSettlementLedger", "setPauseAuthority(address)");
        if (id == _deriveOperationId("PullSettlementLedger", "unpause()")) return ("PullSettlementLedger", "unpause()");
        if (id == _deriveOperationId("PullSettlementLedger", "governedUnpause(bytes32,bytes32,address,bytes32,bytes32)")) return ("PullSettlementLedger", "governedUnpause(bytes32,bytes32,address,bytes32,bytes32)");
        if (id == _deriveOperationId("PullSettlementLedger", "guardianUnpause()")) return ("PullSettlementLedger", "guardianUnpause()");
        if (id == _deriveOperationId("SignatureNonces", "cancelNonce(uint256)")) return ("SignatureNonces", "cancelNonce(uint256)");
        return ("", "");
    }

    function _key(string memory moduleName, string memory signature) private pure returns (bytes32) {
        return keccak256(abi.encode(moduleName, signature));
    }
}