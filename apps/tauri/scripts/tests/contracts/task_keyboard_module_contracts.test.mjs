import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('task list keyboard hook delegates types and keydown dispatch to focused modules', () => {
  const hookPath = path.join(repoRoot, 'app/src/lib/tasks/useTaskListKeyboard.ts');
  const keydownPath = path.join(repoRoot, 'app/src/lib/tasks/useTaskListKeyboard.keydown.ts');
  const typesPath = path.join(repoRoot, 'app/src/lib/tasks/useTaskListKeyboard.types.ts');
  const hookSource = fs.readFileSync(hookPath, 'utf8');
  const keydownSource = fs.readFileSync(keydownPath, 'utf8');
  const typesSource = fs.readFileSync(typesPath, 'utf8');

  assert.ok(hookSource.split('\n').length <= 260, 'useTaskListKeyboard.ts should stay focused on hook state and wiring');
  assert.match(hookSource, /createTaskListKeyboardKeydownHandler/, 'hook root should delegate keydown dispatch');
  assert.match(hookSource, /from '\.\/useTaskListKeyboard\.types'/, 'hook root should preserve public types through a dedicated type module');
  assert.match(keydownSource, /event\.key === 'x'/, 'keydown module should own task action shortcut dispatch');
  assert.match(keydownSource, /tasks\.bulkSelectHint/, 'keydown module should own selection-mode live-region feedback');
  assert.match(typesSource, /interface TaskListKeyboardActions/, 'type module should own task-list keyboard action contracts');
});
