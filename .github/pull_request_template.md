## Linked task

Closes: <!-- exactly one active V2-SC issue -->
Head SHA reviewed: `<!-- full SHA -->`

## Summary

<!-- Explain the smallest cohesive protocol change and why it is required. -->

## Scope and assignment

- [ ] The linked issue has the exact `Stellar Wave` label.
- [ ] The PR author is assigned or explicitly approved by a maintainer.
- [ ] This PR resolves one task; any inseparable pair was pre-approved.
- [ ] Every dependency is safely completed.

## Protocol and security

- [ ] Optimism/EVM only; no Stellar, Soroban, or Freighter runtime.
- [ ] Asset conservation and single-settlement invariants are preserved.
- [ ] Authorization, replay, reentrancy, pause, governance, and upgrade implications were reviewed.
- [ ] Events and interfaces cover every authoritative state transition.
- [ ] Storage layout and deployed compatibility are preserved where applicable.
- [ ] No placeholder address, secret, production mock, or unrelated generated artifact is included.

## Validation

- [ ] Format/lint and compilation pass.
- [ ] Unit and negative-path tests pass.
- [ ] Fuzz, invariant, and property tests pass.
- [ ] Gas and static-security checks pass.
- [ ] ABI/address/event artifacts are synchronized.
- [ ] Required human CODEOWNER approval applies to this exact head SHA.
