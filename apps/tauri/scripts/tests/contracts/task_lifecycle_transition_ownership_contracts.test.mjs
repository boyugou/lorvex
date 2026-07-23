import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const transitionCalls = [
  'apply_lifecycle_transition',
  'apply_completion_transition',
  'apply_cancel_transition',
  'apply_reopen_transition',
];

const approvedProductionCallers = new Set([
  'app/src-tauri/src/commands/tasks/lifecycle/effects.rs',
  'lorvex-cli/src/commands/mutate/tasks/lifecycle_effects/effects.rs',
  'lorvex-workflow/src/lifecycle/cancel.rs',
  'lorvex-workflow/src/lifecycle/completion.rs',
  'lorvex-workflow/src/lifecycle/effects.rs',
  'lorvex-workflow/src/lifecycle/mod.rs',
  'lorvex-workflow/src/lifecycle/reopen.rs',
  'lorvex-workflow/src/lifecycle/transitions.rs',
  'mcp-server/src/tasks/lifecycle/effects.rs',
]);

function rustFilesUnder(relativeDir) {
  const root = path.join(repoRoot, relativeDir);
  const files = [];
  function visit(dir) {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        visit(full);
        continue;
      }
      if (entry.isFile() && entry.name.endsWith('.rs')) {
        files.push(path.relative(repoRoot, full));
      }
    }
  }
  visit(root);
  return files.sort();
}

function stripLineComments(source) {
  return source
    .split('\n')
    .map((line) => line.replace(/\/\/.*$/, ''))
    .join('\n');
}

test('task lifecycle transition calls are owned by surface adapter modules', () => {
  const rustFiles = [
    ...rustFilesUnder('app/src-tauri/src/commands'),
    ...rustFilesUnder('lorvex-cli/src/commands/mutate'),
    ...rustFilesUnder('lorvex-workflow/src/lifecycle'),
    ...rustFilesUnder('mcp-server/src'),
  ];

  const offenders = [];
  for (const relativePath of rustFiles) {
    if (relativePath.includes('/tests/') || relativePath.endsWith('/tests.rs')) {
      continue;
    }

    const source = stripLineComments(fs.readFileSync(path.join(repoRoot, relativePath), 'utf8'));
    const hasTransitionCall = transitionCalls.some((name) => source.includes(`${name}(`));
    if (!hasTransitionCall) {
      continue;
    }

    if (!approvedProductionCallers.has(relativePath)) {
      offenders.push(relativePath);
    }
  }

  assert.deepEqual(
    offenders,
    [],
    `direct lifecycle transition calls must live only in approved adapter modules:\n${offenders.join('\n')}`,
  );
});

test('lifecycle sync fan-out flows through shared sync-plan flushers', () => {
  const workflowSyncPlan = fs.readFileSync(
    path.join(repoRoot, 'lorvex-workflow/src/lifecycle/sync_plan.rs'),
    'utf8',
  );
  const tauriLifecycleQueue = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/sync/runtime/queue/enqueue_lifecycle.rs'),
    'utf8',
  );
  const tauriCompletion = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/tasks/completion/mod.rs'),
    'utf8',
  );
  const tauriCancel = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/tasks/lifecycle/removal/cancel.rs'),
    'utf8',
  );
  const tauriReopen = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/tasks/lifecycle/reopen/mod.rs'),
    'utf8',
  );
  const tauriBatchComplete = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/tasks/batch/complete.rs'),
    'utf8',
  );
  const tauriBatchCancel = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/tasks/batch/cancel.rs'),
    'utf8',
  );
  const mcpComplete = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/lifecycle/writes/complete.rs'),
    'utf8',
  );
  const mcpCancel = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/tasks/lifecycle/writes/cancel.rs'),
    'utf8',
  );
  const cliEffects = fs.readFileSync(
    path.join(repoRoot, 'lorvex-cli/src/commands/mutate/tasks/lifecycle_effects/effects.rs'),
    'utf8',
  );

  assert.match(workflowSyncPlan, /pub struct LifecycleSyncPlan/);
  assert.match(tauriLifecycleQueue, /fn enqueue_lifecycle_sync_plan\(/);

  for (const [label, source] of [
    ['tauri completion', tauriCompletion],
    ['tauri cancel', tauriCancel],
    ['tauri reopen', tauriReopen],
    ['tauri batch completion', tauriBatchComplete],
    ['tauri batch cancel', tauriBatchCancel],
  ]) {
    assert.match(
      source,
      /enqueue_lifecycle_sync_plan\(/,
      `${label} should flush lifecycle related-entity sync through the Tauri sync-plan helper`,
    );
  }

  for (const [label, source] of [
    ['mcp complete', mcpComplete],
    ['mcp cancel', mcpCancel],
  ]) {
    assert.match(source, /flush_sync_plan\(/, `${label} should use the MCP lifecycle sync-plan flusher`);
    assert.doesNotMatch(
      source,
      /enqueue_task_reminder_syncs|enqueue_deleted_task_dependency_syncs|enqueue_task_tag_edge_syncs/,
      `${label} should not open-code lifecycle related-entity sync fan-out`,
    );
  }

  assert.match(cliEffects, /fn flush_lifecycle_sync_plan_with_state\(/);
  for (const functionName of [
    'flush_completion_effects_with_state',
    'flush_cancel_effects_with_state',
    'flush_status_change_effects_with_state',
    'flush_reopen_effects_with_state',
  ]) {
    assert.match(
      cliEffects,
      new RegExp(`fn ${functionName}\\([\\s\\S]*?flush_lifecycle_sync_plan_with_state\\(`),
      `${functionName} should delegate to the shared CLI sync-plan flusher`,
    );
  }
});
