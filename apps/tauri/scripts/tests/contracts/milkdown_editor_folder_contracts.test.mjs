import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const ROOT_FILE = 'app/src/components/ui/MilkdownEditor.tsx';
const SUBTREE = 'app/src/components/ui/milkdown-editor';

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('MilkdownEditor delegates runtime behavior to a folder-backed subtree', () => {
  const rootSource = read(ROOT_FILE);
  const subtreeRoot = path.join(repoRoot, SUBTREE);

  for (const fileName of [
    'MilkdownEditorInner.tsx',
    'MilkdownEditorProvider.tsx',
    'placeholderPlugin.ts',
    'types.ts',
    'useMilkdownAccessibility.ts',
    'useMilkdownLinkOpening.ts',
    'index.ts',
  ]) {
    assert.ok(
      fs.existsSync(path.join(subtreeRoot, fileName)),
      `milkdown editor subtree should include ${fileName}`,
    );
  }

  assert.match(
    rootSource,
    /export \{ default } from '\.\/milkdown-editor';/,
    'MilkdownEditor root should keep the public import path while delegating to the subtree',
  );
  assert.ok(
    rootSource.split('\n').length <= 40,
    'MilkdownEditor root should stay a thin facade after runtime extraction',
  );

  const runtimeSource = read(`${SUBTREE}/MilkdownEditorInner.tsx`);
  assert.match(
    runtimeSource,
    /registerEditorHistoryShortcutHandler\(/,
    'the extracted runtime should continue to route editor-owned undo and redo shortcuts',
  );
  assert.doesNotMatch(
    rootSource,
    /useEditor\(|MutationObserver|addEventListener\(/,
    'MilkdownEditor root should not keep editor setup or DOM side effects inline',
  );
});
