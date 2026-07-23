import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readTypeScriptSources, repoRoot } from './shared.mjs';

test('active task note surfaces use generic placeholder copy and shared task-content projection', () => {
  const taskDetailSource = readTypeScriptSources(
    'app/src/components/task-detail/content/TaskDetailContent.tsx',
    'app/src/components/task-detail/content/detail-content',
  );
  const taskCardControllerSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-card/useTaskCardController.ts'),
    'utf8',
  );
  const checklistEditorSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/TaskChecklistEditor.tsx'),
    'utf8',
  );
  const projectionSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/tasks/contentProjection.ts'),
    'utf8',
  );

  for (const [label, source] of [
    ['TaskDetailContent', taskDetailSource],
  ]) {
    assert.match(
      source,
      /capture\.notesPlaceholder/,
      `${label} should use the generic notes placeholder instead of checklist markdown guidance`,
    );
    assert.doesNotMatch(
      source,
      /task\.notesPlaceholder/,
      `${label} should not surface the legacy checklist-oriented placeholder key`,
    );
  }

  assert.match(
    taskCardControllerSource,
    /projectTaskBodyContent/,
    'task-card controller should consume the shared task-content projection for body snippets',
  );
  assert.doesNotMatch(
    projectionSource,
    /hasMarkdownChecklist/,
    'shared task-content projection should not keep legacy markdown-checklist state',
  );
  assert.match(
    checklistEditorSource,
    /useI18n\(\)|t\('task\.checklist'\)|t\('task\.checklistEmpty'\)|t\('task\.checklistPlaceholder'\)/,
    'task checklist editor should route user-facing copy through i18n keys',
  );
  assert.doesNotMatch(
    checklistEditorSource,
    /No checklist items yet|Add checklist item|Failed to add checklist item|Failed to reorder checklist/,
    'task checklist editor should not keep hardcoded English product copy',
  );
});
