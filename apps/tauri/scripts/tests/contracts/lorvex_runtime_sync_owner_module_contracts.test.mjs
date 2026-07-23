import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, repoRoot } from './shared.mjs';

test('runtime sync-owner is a folder-backed subsystem with separated guard and tests', () => {
  const suiteRoot = path.join(repoRoot, 'lorvex-runtime/src/sync_owner');
  const legacyFlatPath = path.join(repoRoot, 'lorvex-runtime/src/sync_owner.rs');
  const rootPath = path.join(suiteRoot, 'mod.rs');
  const guardPath = path.join(suiteRoot, 'guard.rs');
  const testsDir = path.join(suiteRoot, 'tests');

  assert.equal(fs.existsSync(legacyFlatPath), false, 'sync_owner should not regress to a flat hotspot file');
  assert.ok(fs.existsSync(rootPath), 'sync_owner should be folder-backed');
  assert.ok(fs.existsSync(guardPath), 'sync_owner guard implementation should live in guard.rs');
  // Regression tests were promoted from a single tests.rs to a folder of
  // focused per-domain test files.
  assert.ok(fs.existsSync(testsDir), 'sync_owner regression tests should live under tests/');

  const rootSource = fs.readFileSync(rootPath, 'utf8');
  const guardSource = fs.readFileSync(guardPath, 'utf8');
  const testsSource = fs
    .readdirSync(testsDir)
    .filter((name) => name.endsWith('.rs'))
    .map((name) => fs.readFileSync(path.join(testsDir, name), 'utf8'))
    .join('\n');

  assert.match(rootSource, /^mod guard;$/m, 'sync_owner/mod.rs should register guard.rs');
  assert.match(
    rootSource,
    /^#\[cfg\(test\)\]\s*\nmod tests;$/m,
    'sync_owner/mod.rs should register tests.rs behind cfg(test)',
  );
  assert.equal(
    hasRustUseReexport(rootSource, {
      modulePath: 'guard',
      symbols: ['LeaseReleaseFn', 'ReleasePanicHook', 'SyncOwnerLeaseGuard'],
    }),
    true,
    'sync_owner/mod.rs should re-export public guard types from guard.rs',
  );

  assert.match(rootSource, /pub fn try_acquire_sync_owner_now\(/, 'mod.rs should own lease acquisition SQL');
  assert.match(rootSource, /pub fn renew_sync_owner_now\(/, 'mod.rs should own lease renewal SQL');
  assert.match(rootSource, /pub fn release_sync_owner\(/, 'mod.rs should own lease release SQL');
  assert.doesNotMatch(rootSource, /impl Drop for SyncOwnerLeaseGuard/, 'mod.rs should not own guard drop behavior');

  assert.match(guardSource, /pub struct SyncOwnerLeaseGuard/, 'guard.rs should own the RAII guard type');
  assert.match(guardSource, /impl Drop for SyncOwnerLeaseGuard/, 'guard.rs should own drop-based release');
  assert.match(guardSource, /catch_unwind/, 'guard.rs should preserve panic-safe release semantics');

  for (const testName of [
    'concurrent_acquirers_race_resolves_deterministically',
    'guard_drop_releases_lease_when_caller_panics',
    'release_panic_hook_receives_lease_owner_and_message',
    'boundary_expiry_belongs_to_prior_owner',
  ]) {
    assert.match(testsSource, new RegExp(`fn ${testName}\\(`), `tests.rs should keep ${testName}`);
  }

  assert.ok(rootSource.split('\n').length <= 320, 'sync_owner/mod.rs should stay focused on lease SQL orchestration');
  assert.ok(guardSource.split('\n').length <= 260, 'sync_owner/guard.rs should stay focused on guard plumbing');
});
