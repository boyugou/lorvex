import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('TaskNotesEditor is organized as a folder-backed subsystem with editor and markdown modules', () => {
  const editorSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/task-notes-editor/TaskNotesEditor.tsx'),
    'utf8',
  );
  const bodyContentSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/task-notes-editor/TaskBodyContent.tsx'),
    'utf8',
  );
  const inlineMarkdownSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/task-notes-editor/inlineMarkdown.tsx'),
    'utf8',
  );

  assert.equal(
    fs.existsSync(path.join(repoRoot, 'app/src/components/task-detail/TaskNotesEditor.tsx')),
    false,
    'TaskNotesEditor should not keep a root re-export alias',
  );
  assert.match(
    editorSource,
    /export default function TaskNotesEditor\(/,
    'TaskNotesEditor implementation should live in the task-notes-editor subtree',
  );
  assert.ok(
    fs.existsSync(path.join(repoRoot, 'app/src/components/task-detail/task-notes-editor/TaskBodyContent.tsx')),
    'TaskBodyContent module should exist in the task-notes-editor subtree',
  );
  assert.match(
    bodyContentSource,
    /import \{ renderInlineMarkdown } from '\.\/inlineMarkdown';/,
    'TaskBodyContent should delegate inline markdown rendering to a dedicated helper module',
  );
  assert.match(
    inlineMarkdownSource,
    /function ExternalLink\(/,
    'Task notes inline markdown should keep external link handling in a dedicated helper module',
  );
});
