import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const CONTENT_ROOT = 'app/src/components/task-detail/content/TaskDetailContent.tsx';
const SECTION_ROOT = 'app/src/components/task-detail/content/detail-content';

test('TaskDetailContent delegates local UI sections to a folder-backed subtree', () => {
  const contentSource = fs.readFileSync(path.join(repoRoot, CONTENT_ROOT), 'utf8');
  const sectionRoot = path.join(repoRoot, SECTION_ROOT);

  for (const fileName of [
    'TaskDetailBodySections.tsx',
    'TaskDetailHeader.tsx',
    'TaskDetailInlineTags.tsx',
    'TaskDetailMoreSection.tsx',
    'TaskDetailOverflowMenu.tsx',
    'TaskDetailTitleEditor.tsx',
    'index.ts',
  ]) {
    assert.ok(
      fs.existsSync(path.join(sectionRoot, fileName)),
      `task detail content subtree should include ${fileName}`,
    );
  }

  assert.match(
    contentSource,
    /from '\.\/detail-content';/,
    'TaskDetailContent root should import local UI sections from the detail-content subtree',
  );
  assert.doesNotMatch(
    contentSource,
    /function (?:OverflowMenuItem|TaskDetailInlineTags|TaskDetailMoreSection)\b/,
    'TaskDetailContent root should not keep local section component implementations inline',
  );
  assert.ok(
    contentSource.split('\n').length <= 240,
    'TaskDetailContent root should stay a composition boundary after section extraction',
  );
});
