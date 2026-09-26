# Runbook: Emergency Pause (V2)

Operational procedure for pausing and recovering the protocol using the
canonical V2 emergency surface.

## Who can pause

| Actor | Surface | Capability |
|---|---|---|
| Emergency Council | `EmergencyController.activatePause` | Escalate protocol pause levels 1–3 (rapid response) |
| DAO Governance | `EmergencyController.activatePause` / `liftPause` | Escalate any level; the only authority that can de-escalate |
| Timelock Controller | `EmergencyController.activatePause` | Level 1 only, subject to a cooldown between activations |
| PAUSE_INITIATOR | `EmergencyGatekeeper.pause` | Scoped pause; can never unpause |
| PAUSE_RESOLVER | `EmergencyGatekeeper.pause` / `unpause` | Scoped pause and post-remediation resolution |

Every pause action emits an immutable audit event
(`EmergencyPauseActivated`, `EmergencyPaused`, and companions in
`docs/event-catalogue-v1.md`).

## When pause is allowed

- Scoped pauses (`EmergencyGatekeeper.pause(scope)`) are allowed while the
  protocol-level controller is not escalated beyond the scope's configured
  tolerance (`setScopeMaxPauseLevel`).
- Global escalation via `EmergencyController` contains every scope; at
  level 3 (shutdown) the gatekeeper treats all scopes as paused regardless
  of tolerance.
- If the wired `EmergencyController` is unavailable (unreachable,
  reverts, or returns malformed data), the gatekeeper fails closed: reads
  classify every scope as paused and mutations revert.

## How to verify pause

1. `EmergencyGatekeeper.paused(scope)` — must return `true` for the
   affected scope(s).
2. `EmergencyGatekeeper.locallyPaused(scope)` — `true` means a scoped
   pause record exists (vs. containment by protocol escalation).
3. `EmergencyController.getPauseLevel()` — the protocol-wide level.
4. Attempt a gated mutation against a canary module; it must revert with
   `V2Errors.ProtocolPaused`.

## Recovery procedure

1. **Remediate the incident** off-chain; agree the remediation record.
2. **De-escalate the protocol level**: only `DAO_Governance` may call
   `EmergencyController.liftPause`.
3. **Complete the staged recovery steps** on the `EmergencyController`
   (`completeRecoveryStep` × 3 by the recovery executor).
4. **Resolve scoped pauses**: `PAUSE_RESOLVER` calls
   `EmergencyGatekeeper.unpause(scope)` for each scope. Resolution is
   rejected while the protocol level exceeds the scope's tolerance.
5. **Verify resumption**: `paused(scope)` returns `false` and a canary
   gated mutation succeeds. Escrowed balances must be unchanged across
   the pause window.

Dependency rewiring (`EmergencyGatekeeper.setEmergencyController`) is
timelocked: replacing or removing a wired controller requires waiting
`emergencyRewireDelay` (default 1 hour, bounded [1 hour, 30 days]).
Wiring a controller when none is wired is immediate, because that
direction only ever tightens control.

## Exercise suite

`test/v2/EmergencyPauseRecoveryExercise.t.sol` rehearses this runbook
against the canonical contracts:

| Drill group | What is proven |
|---|---|
| Configuration | Invalid admin/initiator/resolver, delay bounds, hostile dependency surface, scope-tolerance bounds — all fail closed |
| Compromised roles | Unprivileged callers cannot pause/unpause; the initiator can never unpause |
| Selective pause | Pausing one scope freezes it while sibling scopes stay operational; escrow survives |
| Full pause | Protocol levels 1–3 contain scopes per tolerance; shutdown contains everything and blocks resolution |
| Dependency failure | Reverting, short-returndata, and corrupt-returndata dependencies fail closed; recovery requires a healthy dependency |
| Timelock | Rewiring or unwiring the dependency waits the enforced delay; the new authority takes effect immediately after |
| Remediation & resumption | De-escalation, staged resolution, and safe resumption with intact escrow |

Fuzz properties: `test/v2/EmergencyGatekeeperFuzz.t.sol`.
Invariants (pause effectiveness, escalation containment, exact ghost
bookkeeping): `test/v2/EmergencyGatekeeperInvariant.t.sol`.
