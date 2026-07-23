import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('Eisenhower and Kanban controllers delegate write actions to dedicated runtime hooks', () => {
  const eisenhowerControllerSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/eisenhower/useEisenhowerController.ts'),
    'utf8',
  );
  const eisenhowerActionsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/eisenhower/useEisenhowerPriorityActions.ts'),
    'utf8',
  );
  const kanbanControllerSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/kanban/useKanbanController.ts'),
    'utf8',
  );
  const kanbanActionsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/kanban/useKanbanColumnActions.ts'),
    'utf8',
  );

  assert.match(
    eisenhowerControllerSource,
    /import \{ useEisenhowerPriorityActions \} from '\.\/useEisenhowerPriorityActions';/,
    'Eisenhower controller should delegate priority updates to a dedicated action hook',
  );
  assert.doesNotMatch(eisenhowerControllerSource, /useMutation\(\{|updateTask\(/);
  assert.match(eisenhowerActionsSource, /export function useEisenhowerPriorityActions\(/);
  assert.match(eisenhowerActionsSource, /useMutation(?:<[^>]+>)?\(\{/);

  assert.match(
    kanbanControllerSource,
    /import \{ useKanbanColumnActions \} from '\.\/useKanbanColumnActions';/,
    'Kanban controller should delegate column-move mutations to a dedicated action hook',
  );
  assert.doesNotMatch(kanbanControllerSource, /useMutation(?:<[^>]+>)?\(\{|completeTask\(|reopenTask\(|updateTask\(/);
  assert.match(kanbanActionsSource, /export function useKanbanColumnActions\(/);
  assert.match(kanbanActionsSource, /useMutation(?:<[^>]+>)?\(\{/);
});
