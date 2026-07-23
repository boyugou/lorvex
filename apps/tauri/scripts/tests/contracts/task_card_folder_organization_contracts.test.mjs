import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('TaskCard is organized as a folder-backed subsystem with controller content and action modules', () => {
  // The historical `app/src/components/TaskCard.tsx` shim that re-exported
  // `./task-card/TaskCard` was retired once every importer was migrated to
  // the canonical `./task-card/TaskCard` path; CLAUDE.md forbids
  // backward-compat re-exports. The contract now asserts there is NO
  // legacy shim — exactly one canonical TaskCard component exists, and
  // the `task-card/` folder owns the entire surface.
  const legacyShimPath = path.join(repoRoot, 'app/src/components/TaskCard.tsx');
  assert.equal(
    fs.existsSync(legacyShimPath),
    false,
    'app/src/components/TaskCard.tsx should NOT exist — task-card/TaskCard is the canonical entry, no re-export shim',
  );
  const viewSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/task-card/TaskCard.tsx'), 'utf8');
  const controllerSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/task-card/useTaskCardController.ts'), 'utf8');
  const contentSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/task-card/TaskCardContent.tsx'), 'utf8');
  const actionSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/task-card/TaskCardActionButton.tsx'), 'utf8');
  const supportSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/task-card/support.ts'), 'utf8');
  const projectionSource = fs.readFileSync(path.join(repoRoot, 'app/src/lib/tasks/contentProjection.ts'), 'utf8');

  assert.match(viewSource, /useTaskCardController\(/);
  assert.match(viewSource, /<TaskCardActionButton/);
  assert.match(viewSource, /<TaskCardContent/);
  assert.doesNotMatch(
    viewSource,
    /const taskCardMountedRef = useRef\(true\);|await completeTask\(|await reopenTask\(/,
    'TaskCard composition root should delegate async mutation lifecycle work to the controller',
  );

  assert.match(controllerSource, /export function useTaskCardController\(/);
  assert.match(controllerSource, /const taskCardMountedRef = useMounted\(\);/);
  assert.match(controllerSource, /reportClientError\(/);
  assert.match(
    controllerSource,
    /projectTaskBodyContent/,
    'task-card controller should use the shared task content projection for note/body parsing',
  );

  assert.match(contentSource, /export.*TaskCardContent.*=.*memo\(function TaskCardContent\(|export function TaskCardContent\(/);
  assert.doesNotMatch(
    contentSource,
    /useQueryClient|toast|completeTask|reopenTask/,
    'TaskCard content should stay focused on rendering task presentation (useState/useRef are OK for inline editing)',
  );

  assert.match(actionSource, /export function TaskCardActionButton\(/);
  assert.doesNotMatch(
    actionSource,
    /useQueryClient|useState|toast|parseChecklistProgress/,
    'TaskCard action buttons should stay focused on button affordances instead of controller state',
  );

  assert.match(supportSource, /export interface TaskCardProps/);
  assert.match(supportSource, /export function parseChecklistProgress\(/);
  assert.match(projectionSource, /export function projectTaskBodyContent\(/);
  assert.doesNotMatch(
    projectionSource,
    /hasMarkdownChecklist|checklistProgress/,
    'task content projection should not own legacy markdown-checklist state',
  );
});
