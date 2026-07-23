import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from '../shared.mjs';

const VERIFIER = path.join(repoRoot, 'scripts/verify/ipc_command_parity.mjs');

function runVerifier() {
  return spawnSync(process.execPath, [VERIFIER], {
    cwd: repoRoot,
    encoding: 'utf8',
  });
}

// #4406 — every `#[tauri::command]` handler must have at least one
// `invoke('name', …)` call site under `app/src/lib/ipc/**`, and every
// invoke call must point at a real handler. The verifier is wired
// into `verify:repo-governance`; this contract test makes that
// wiring observable from the `test:contract-verifiers` suite and
// double-prints the failing-pair details so the suite log is enough
// to diagnose the drift.
test('ipc_command_parity verifier passes on current tree', () => {
  const result = runVerifier();
  if (result.status !== 0) {
    const detail = [
      `verifier exited ${result.status} (signal=${result.signal ?? 'none'}).`,
      result.stdout ? `stdout:\n${result.stdout}` : '',
      result.stderr ? `stderr:\n${result.stderr}` : '',
    ]
      .filter(Boolean)
      .join('\n');
    assert.fail(detail);
  }
  // Sanity check the counts summary — guards against a future
  // regression where the verifier exits 0 with both sides empty
  // (which would be a silent "success" if a path glob ever
  // regressed). 100+ commands is well below current head and well
  // above any reasonable empty-state false positive.
  assert.match(
    result.stdout,
    /OK ipc_command_parity: (\d+) #\[tauri::command\] handlers, (\d+) invoke\('name'\) call sites/,
  );
  const match = result.stdout.match(
    /(\d+) #\[tauri::command\] handlers, (\d+) invoke\('name'\)/,
  );
  if (match) {
    const handlers = Number(match[1]);
    const callers = Number(match[2]);
    assert.ok(handlers >= 100, `expected ≥100 handlers, got ${handlers}`);
    assert.ok(callers >= 100, `expected ≥100 caller sites, got ${callers}`);
  }
});
