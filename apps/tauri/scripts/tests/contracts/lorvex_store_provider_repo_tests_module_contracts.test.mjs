import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('provider repo runtime keeps unit tests in a dedicated tests module', () => {
  const runtimePath = path.join(repoRoot, 'lorvex-store/src/repositories/provider_repo/mod.rs');
  const testsPath = path.join(repoRoot, 'lorvex-store/src/repositories/provider_repo/tests.rs');
  const runtimeSource = fs.readFileSync(runtimePath, 'utf8');

  assert.match(
    runtimeSource,
    /#\[cfg\(test\)\]\s*mod tests;/,
    'provider_repo.rs should declare tests as a sibling module',
  );
  assert.doesNotMatch(
    runtimeSource,
    /#\[cfg\(test\)\]\s*mod tests\s*\{/,
    'provider_repo.rs should not keep provider repo unit tests inline',
  );
  assert.ok(fs.existsSync(testsPath), 'provider_repo/tests.rs should own provider repo unit tests');

  const testsSource = fs.readFileSync(testsPath, 'utf8');
  for (const testName of [
    'resolved_links_with_cache_hit',
    'resolved_links_stale_when_scope_success_is_too_old',
    'scope_queryable_when_availability_enabled',
    'upsert_provider_event_rejects_stale_last_seen_at',
  ]) {
    assert.match(
      testsSource,
      new RegExp(`\\bfn\\s+${testName}\\b`),
      `provider_repo/tests.rs should own ${testName}`,
    );
  }
});
