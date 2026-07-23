import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

function readRepoFile(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('lifecycle side-effect fan-out routes through shared sync plans across runtime surfaces', () => {
  const workflowPlan = readRepoFile('lorvex-workflow/src/lifecycle/sync_plan.rs');
  assert.match(workflowPlan, /pub struct LifecycleSyncPlan/);
  assert.match(workflowPlan, /pub struct StatusSideEffectSyncPlan/);
  assert.match(workflowPlan, /pub fn from_completion/);
  assert.match(workflowPlan, /pub fn from_cancel/);
  assert.match(workflowPlan, /pub fn from_reopen/);
  assert.match(workflowPlan, /pub fn from_transition/);

  const tauriLifecycleQueue = readRepoFile(
    'app/src-tauri/src/commands/sync/runtime/queue/enqueue_lifecycle.rs',
  );
  assert.match(tauriLifecycleQueue, /pub\(crate\) fn enqueue_lifecycle_sync_plan\(/);
  assert.match(tauriLifecycleQueue, /LifecycleSyncPlan::from_transition\(transition\)/);

  const cliLifecycleEffects = readRepoFile(
    'lorvex-cli/src/commands/mutate/tasks/lifecycle_effects/effects.rs',
  );
  assert.match(cliLifecycleEffects, /fn flush_lifecycle_sync_plan_with_state\(/);
  assert.match(cliLifecycleEffects, /LifecycleSyncPlan::from_completion\(result\)/);
  assert.match(cliLifecycleEffects, /LifecycleSyncPlan::from_cancel\(result\)/);
  assert.match(cliLifecycleEffects, /LifecycleSyncPlan::from_reopen\(result\)/);

  const mcpLifecycleEffects = readRepoFile('mcp-server/src/tasks/lifecycle/effects.rs');
  assert.match(mcpLifecycleEffects, /pub\(crate\) fn flush_sync_plan\(/);
  assert.match(mcpLifecycleEffects, /plan\.spawned_successor_checklist_item_ids/);
  assert.match(mcpLifecycleEffects, /plan\.rewired_focus_schedule_dates/);
});

test('MCP lifecycle batch and pre-completed create paths do not re-open-code plan fan-out', () => {
  const guardedFiles = [
    'mcp-server/src/tasks/batch/complete.rs',
    'mcp-server/src/tasks/batch/cancel_by_ids/mod.rs',
    'mcp-server/src/tasks/batch/reopen.rs',
  ];

  for (const relativePath of guardedFiles) {
    const source = readRepoFile(relativePath);
    assert.match(source, /flush_sync_plan\(/, `${relativePath} should call the MCP plan flusher`);
    assert.match(
      source,
      /LifecycleSyncPlan::from_(completion|cancel|reopen|transition)\(/,
      `${relativePath} should construct the workflow-owned lifecycle plan`,
    );
    assert.doesNotMatch(
      source,
      /\b(enqueue_task_tag_edge_syncs|ENTITY_TASK_CHECKLIST_ITEM|ENTITY_TASK_REMINDER|ENTITY_CURRENT_FOCUS|ENTITY_FOCUS_SCHEDULE)\b/,
      `${relativePath} must not manually fan out lifecycle child/focus sync buckets`,
    );
  }
});
