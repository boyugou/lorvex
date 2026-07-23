import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('calendar recurrence runtime keeps unit tests in a dedicated tests module', () => {
  const runtimePath = path.join(repoRoot, 'lorvex-store/src/calendar_timeline/recurrence.rs');
  const testsPath = path.join(repoRoot, 'lorvex-store/src/calendar_timeline/recurrence/tests.rs');
  const testsDir = path.join(repoRoot, 'lorvex-store/src/calendar_timeline/recurrence/tests');
  const runtimeSource = fs.readFileSync(runtimePath, 'utf8');

  assert.match(
    runtimeSource,
    /#\[cfg\(test\)\]\s*mod tests;/,
    'recurrence.rs should declare tests as a sibling module',
  );
  assert.doesNotMatch(
    runtimeSource,
    /#\[cfg\(test\)\]\s*mod tests\s*\{/,
    'recurrence.rs should not keep the recurrence unit tests inline',
  );
  assert.ok(fs.existsSync(testsPath), 'recurrence/tests.rs should own the recurrence test facade');
  assert.ok(fs.existsSync(testsDir), 'recurrence/tests/ should own recurrence unit test modules');

  const testsSource = fs.readFileSync(testsPath, 'utf8');
  for (const moduleName of ['validation', 'recurs_on_date', 'count_end', 'weekly']) {
    assert.match(
      testsSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `recurrence/tests.rs should register ${moduleName}.rs`,
    );
  }

  const moduleOwnership = {
    'validation.rs': 'decrement_recurrence_count_accepts_uncapped_positive_count',
    'recurs_on_date.rs': 'recurs_on_date_rejects_excessive_count_for_expansion_budget',
    'count_end.rs': 'count_end_rejects_excessive_count',
    'weekly.rs': 'byday_occurrence_next_interval',
  };

  for (const [fileName, testName] of Object.entries(moduleOwnership)) {
    const moduleSource = fs.readFileSync(path.join(testsDir, fileName), 'utf8');
    assert.match(
      moduleSource,
      new RegExp(`\\bfn\\s+${testName}\\b`),
      `recurrence/tests/${fileName} should own ${testName}`,
    );
  }
});
