import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const repoRoot = process.cwd();

function readSource(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('task list actions split lifecycle, scheduling, metadata, and overlay families', () => {
  const composer = readSource('app/src/lib/tasks/useTaskListActions.ts');
  const lifecycle = readSource('app/src/lib/tasks/taskActions/lifecycle.ts');
  const scheduling = readSource('app/src/lib/tasks/taskActions/scheduling.ts');
  const metadata = readSource('app/src/lib/tasks/taskActions/metadata.ts');
  const overlays = readSource('app/src/lib/tasks/taskActions/overlays.ts');
  const shared = readSource('app/src/lib/tasks/taskActions/shared.ts');

  for (const hookName of [
    'useTaskLifecycleActions',
    'useTaskSchedulingActions',
    'useTaskMetadataActions',
    'useTaskOverlayActions',
  ]) {
    assert.match(composer, new RegExp(`${hookName}\\(`));
  }

  assert.doesNotMatch(composer, /completeTask\(|cancelTask\(|deferTaskUntil\(|updateTask\(|enterFocusModeWindow\(|dispatchTaskListElementEvent\(/);
  assert.match(lifecycle, /completeTask\(/);
  assert.match(lifecycle, /cancelTask\(/);
  assert.match(scheduling, /deferTaskUntil\(/);
  assert.match(scheduling, /buildDueDatePatch/);
  assert.match(metadata, /onSetPriority/);
  assert.match(metadata, /onToggleRecurrence/);
  assert.match(overlays, /dispatchTaskListElementEvent\(/);
  assert.match(overlays, /usePickerState/);
  assert.match(shared, /export function getActiveTask/);
  assert.match(shared, /export function undoableAction/);
});
