import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const repoRoot = process.cwd();

function readSource(relativePath: string): string {
  return readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('Milkdown task-edit surfaces retain update undo toasts after persisted saves', () => {
  const sources = [
    readSource('app/src/components/task-detail/controller/drafts.ts'),
  ];

  for (const source of sources) {
    assert.match(source, /showUndoOnlyToast\(/);
    assert.match(source, /undo_token/);
  }
});

test('desktop history shortcuts explicitly route editor-owned undo and redo', () => {
  const desktopMainWindow = readSource('app/src/app-shell/main-window/DesktopMainWindow.tsx');
  const milkdownEditor = [
    readSource('app/src/components/ui/MilkdownEditor.tsx'),
    readSource('app/src/components/ui/milkdown-editor/MilkdownEditorInner.tsx'),
  ].join('\n');

  assert.match(desktopMainWindow, /getHistoryShortcutAction\(/);
  assert.match(desktopMainWindow, /resolveHistoryShortcutRoute\(/);
  assert.match(desktopMainWindow, /resolveUnhandledEditorHistoryShortcutRoute\(/);
  assert.match(desktopMainWindow, /dispatchEditorHistoryShortcut\(/);
  assert.match(milkdownEditor, /registerEditorHistoryShortcutHandler\(/);
});
