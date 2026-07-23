# Sync Recovery Playbook
This playbook is the operational runbook for recovering the local file sync bridge (`sync_outbox` + `sync_checkpoints`) when data diverges or sync is stuck.

---

## 1. Fast Triage

1. Open Settings → `Sync Queue`.
2. Record these fields before changing anything:
   - `pending_count`
   - `retrying_count`
   - `failed_count`
   - `last_success_at`
   - `last_pull_at`
   - `last_error`
3. Run one manual `Sync now` and re-check whether counters move.

If `pending_count` is decreasing and `failed_count` stays at `0`, do not intervene.

---

## 2. Failure Modes and Actions

## A) Push write errors (cannot write sync files)

Symptoms:
- `push_write_errors > 0`
- `last_error` contains file path or permission failure

Actions:
1. Verify the configured filesystem-bridge root path exists and is writable by the current user.
2. If the path points to a provider-backed folder, ensure the folder is fully
   hydrated locally.
3. Re-run `Sync now`.
4. If still failing, switch to a fresh folder path and run `Sync now` again.

Expected recovery signal:
- `push_write_errors` returns to `0`
- `last_success_at` updates
- `last_error` is cleared

## B) Pull parse errors (invalid remote event files)

Symptoms:
- `pull_parse_errors > 0`
- `last_error` mentions JSON parse or unsupported event shape

Actions:
1. Inspect malformed `.json` event files in shared folder.
2. Remove or quarantine only malformed files.
3. Re-run `Sync now`.

Expected recovery signal:
- `pull_parse_errors` drops
- `last_pull_at` updates

## C) Retries accumulating (`failed_count` increasing)

Symptoms:
- `retrying_count` / `failed_count` increases over time
- the sync folder is writable, but provider download/upload state is not
  converging

Actions:
1. Fix root cause first (A or B).
2. Run `Sync now` until pending queue drains.
3. Confirm retried events transition to `synced_at`.

Expected recovery signal:
- `retrying_count` and `failed_count` trend to `0`
- `pending_count` decreases

## D) Conflict suspicion (same entity edited on two devices)

Current policy:
- Version ordering is a strict total order: `(updated_at, device_id, event_id)`.
- Duplicate event IDs are ignored.
- Stale events are recorded but not applied.

Actions:
1. Verify local final state for affected entity.
2. If final state is wrong, apply corrective edit on the intended device (creates newer event).
3. Run `Sync now` on both devices.

Expected recovery signal:
- newer corrective edit converges everywhere
- no repeated flip-flop after additional pulls

---

## 3. Snapshot Rollback Procedure (Operator Safe Path)

Use this when import/sync remediation may be risky.

1. In Settings → `Your Data`, click `Export Data` to create a rollback ZIP export.
   - the app always writes a `.zip` archive and appends `.zip` if the filename omits it
2. Perform import or other recovery operation.
3. If outcome is wrong:
   - click `Import from File`
   - choose the rollback `.zip` archive
   - click `Import`

This restores data from the pre-change ZIP export in one session.

---

## 4. Verification Checklist (after recovery)

All must hold:
- `pending_count == 0` (or steadily decreasing under active writes)
- `failed_count == 0`
- `last_success_at` is recent
- `last_pull_at` is recent
- `last_error` is empty
- Known conflict entities match expected final values

If any item fails repeatedly after two manual sync attempts, capture `last_error` and open a bug with exact timestamps and entity IDs.

---

## 5. Reusable Evidence Template

Use the sync-recovery report scaffold to keep issue updates consistent and faster to write.

- Template: `docs/execution/templates/manual-gate-sync-recovery.md.tmpl`
- Generate a local report scaffold:

```bash
npm run docs:manual-gate:report -- --template sync-recovery --date YYYY-MM-DD --issue <current-issue> --commit <git-sha>
```

Use exactly one current evidence target: `--issue <current-issue>`, `--pr <current-pr>`, or `--release-target <release-target>`.

- Verify evidence contract before posting:

```bash
npm run verify:manual-gate-evidence
```

- Evidence freshness window is 14 days; release CI enforces strict freshness with:

```bash
npm run verify:manual-gate-evidence -- --enforce-release
```

Default output path:
`artifacts/manual-gates/sync-recovery/YYYY-MM-DD/<target-slug>.md`

Do not commit generated evidence. Summarize the run in the linked issue/PR and keep attachments alongside the local artifact bundle. Fill `Evidence permalink` with the posted GitHub issue/PR comment URL before treating the gate as complete.

## Automation Bridge Coverage (#224)

Automated subset (deterministic replay/retry guards):

```bash
npm run manual-gate:smoke
```

This command automates the deterministic sync-recovery subset:
- sync replay/LWW/idempotency test slice
- sync retry + mark-synced behavior slice
- evidence/template contract checks

Still manual by design:
- filesystem permission and provider hydration/operator environment failure modes
- human-run remediation steps in Settings UI (`Sync now`, folder switch, snapshot rollback)
- cross-device final-state confirmation after corrective edits
