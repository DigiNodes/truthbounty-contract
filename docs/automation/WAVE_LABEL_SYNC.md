# Wave lifecycle label synchronization

This automation manages TruthBounty's **internal** contribution-workflow labels for the new V2 smart-contract backlog. It does not publish issues to Drips.

## Protected scope

The synchronizer is deliberately restricted to:

- repository: `DigiNodes/truthbounty-contract`
- issues: `#352` through `#391`
- identifiers: `V2-SC-001` through `V2-SC-040`
- required issue-body marker: `**Candidate state:** \`wave-candidate\``

Before any write, the script validates the complete issue set. It stops if an issue is missing, closed, is a pull request, has an unexpected identifier, lacks the candidate marker, has multiple lifecycle labels, or contains a forbidden activation label.

Historical issues outside this exact range are never selected.

## Lifecycle labels

| Label | Meaning |
|---|---|
| `wave-candidate` | Valid backlog item awaiting maintainer review |
| `wave-reviewed` | Scope, dependencies, security, and acceptance criteria have been reviewed |
| `wave-ready` | Contributor-ready and eligible for a separate publication decision |
| `wave-blocked` | Meaningful work that cannot start until a dependency or decision is resolved |

The synchronizer creates or updates these four label definitions. It adds `wave-candidate` only when a protected issue has no lifecycle label. It never regresses `wave-reviewed`, `wave-ready`, or `wave-blocked` to `wave-candidate`.

## Drips activation boundary

The following labels are forbidden in this automation:

- `Stellar Wave`
- `stellar-wave`
- `drips-wave`

`Stellar Wave` is the external Drips activation label. Applying it is a later, separate maintainer-controlled publication action after issue readiness and points-budget review. This workflow never creates or applies it.

## Automatic checks

Pull requests and pushes to `main` that change the synchronizer run a read-only plan:

1. validate Bash syntax;
2. validate the JSON configuration;
3. inspect every protected issue;
4. print the proposed changes.

These events receive only `contents: read` and `issues: read` permissions. They cannot change labels or issues.

## Applying the reviewed plan

After this change is merged:

1. Open **Actions** in `DigiNodes/truthbounty-contract`.
2. Select **Sync Wave lifecycle labels**.
3. Choose **Run workflow** on `main`.
4. Set `apply` to `true`.
5. Enter the exact confirmation `DigiNodes/truthbounty-contract`.
6. Review the completed job summary and confirm that all protected issues have exactly one lifecycle label.

A manual dispatch with `apply=false`, a missing confirmation, or a different confirmation performs the read-only plan and skips the write job.

The apply job runs only after the plan succeeds and receives `issues: write` only for that job.

## Local dry run

With GitHub CLI authentication that can read the repository:

```bash
GH_REPO=DigiNodes/truthbounty-contract \
  bash automation/sync-wave-labels.sh --dry-run
```

The default mode is also dry-run. Use `--apply` only after reviewing the complete plan.

## Idempotency and failure behavior

Repeated approved runs are safe:

- existing lifecycle label definitions are reconciled to the configured color and description;
- issues already carrying one lifecycle state remain in that state;
- only protected issues without a lifecycle state receive `wave-candidate`;
- a failed preflight produces no mutations;
- post-apply verification fails the run if any protected issue lacks exactly one lifecycle label or has a forbidden activation label.

## Rollback

If the initial candidate assignment must be reverted, remove only `wave-candidate` from the affected issues in the protected V2 range. Do not delete repository-wide lifecycle labels and do not modify historical issues. Investigate and correct the configuration or issue metadata before another approved apply run.
