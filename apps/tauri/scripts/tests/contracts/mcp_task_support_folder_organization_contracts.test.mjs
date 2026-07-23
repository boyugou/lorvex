import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('server_task_support is organized as a folder-backed subsystem with normalization status and tests modules', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/support.rs'),
    'utf8',
  );
  const normalizationSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/support/normalization.rs'),
    'utf8',
  );
  const statusSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/support/status.rs'),
    'utf8',
  );
  const testsSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/support/tests.rs'),
    'utf8',
  );

  for (const moduleName of ['normalization', 'status']) {
    assert.match(rootSource, new RegExp(`^mod ${moduleName};$`, 'm'));
  }
  assert.match(rootSource, /^#\[cfg\(test\)\]$/m);
  assert.match(rootSource, /^mod tests;$/m);
  assert.match(rootSource, /^pub\(crate\) use normalization::/m);
  assert.match(rootSource, /^pub\(crate\) use status::/m);

  // urgency module was removed (#1515) — verify it is no longer declared
  assert.doesNotMatch(
    rootSource,
    /^mod urgency;$/m,
    'server_task_support root should not declare urgency module after removal',
  );
  assert.doesNotMatch(
    rootSource,
    /pub\(crate\) use urgency::/,
    'server_task_support root should not re-export urgency helpers after removal',
  );
  assert.doesNotMatch(
    rootSource,
    /\npub\(crate\) (?:const )?fn compute_urgency_score_for_timezone_name_at\(|\npub\(crate\) (?:const )?fn normalize_due_date_input_for_conn\(|\npub\(crate\) (?:const )?fn normalize_task_status\(|\n(?:const )?fn priority_base\(|\n#\[cfg\(test\)\]\nmod tests \{/,
    'server_task_support root should remain a composition root after folder extraction',
  );

  assert.match(normalizationSource, /\npub\(crate\) (?:const )?fn normalize_due_date_input_for_conn\(/);
  assert.match(normalizationSource, /\npub\(crate\) (?:const )?fn normalize_nullable_due_date_patch_for_conn\(/);
  assert.match(normalizationSource, /\npub\(crate\) (?:const )?fn normalize_task_priority\(/);
  assert.match(normalizationSource, /\npub\(crate\) (?:const )?fn recurrence_base_date_for_conn_at\(/);
  assert.match(statusSource, /\npub\(crate\) (?:const )?fn status_filter_to_sql_value\(/);
  assert.match(statusSource, /\npub\(crate\) (?:const )?fn task_status_value_to_str\(/);
  // `normalize_task_status` was deleted: typed `TaskStatusValue` enums
  // arrive from serde-validated args, so the legacy normalize gate
  // became unreachable. Verify the comment marker remains so a future
  // refactor doesn't reintroduce a string-shaped status normalizer.
  assert.match(statusSource, /`normalize_task_status` was deleted/);
  assert.match(testsSource, /\n(?:const )?fn normalize_due_date_input_resolves_aliases\(/);
});
