import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  installContextMenuKeyboardRuntime,
  resolveContextMenuKeyAction,
  resolveContextMenuPosition,
  resolveContextSubmenuPosition,
  resolveNextContextMenuHighlightIndex,
  runContextMenuKeyAction,
  type ContextMenuKeyAction,
  type ContextMenuKeyEventLike,
} from '../../../app/src/components/context-menu/ContextMenu.runtime';

function buildKeyEvent(
  actionKey: string,
  overrides: Partial<ContextMenuKeyEventLike> = {},
): ContextMenuKeyEventLike {
  return {
    key: actionKey,
    preventDefault() {},
    stopImmediatePropagation() {},
    stopPropagation() {},
    ...overrides,
  };
}

test('context menu position clamps to viewport padding on every edge', () => {
  assert.deepEqual(
    resolveContextMenuPosition({ x: 120, y: 80 }, { width: 180, height: 120 }, { width: 500, height: 400 }),
    { x: 120, y: 80 },
  );
  assert.deepEqual(
    resolveContextMenuPosition({ x: 480, y: 390 }, { width: 180, height: 120 }, { width: 500, height: 400 }),
    { x: 312, y: 272 },
  );
  assert.deepEqual(
    resolveContextMenuPosition({ x: -20, y: -10 }, { width: 180, height: 120 }, { width: 500, height: 400 }),
    { x: 8, y: 8 },
  );
  assert.deepEqual(
    resolveContextMenuPosition({ x: 20, y: 20 }, { width: 800, height: 600 }, { width: 500, height: 400 }),
    { x: 8, y: 8 },
  );
});

test('context submenu position opens toward available space and avoids viewport top overflow', () => {
  assert.deepEqual(
    resolveContextSubmenuPosition(
      { width: 180, right: 220, top: 80 },
      { width: 160, height: 120 },
      { width: 600, height: 500 },
    ),
    { left: 178, top: 0 },
  );
  assert.deepEqual(
    resolveContextSubmenuPosition(
      { width: 180, right: 570, top: 320 },
      { width: 160, height: 140 },
      { width: 600, height: 420 },
    ),
    { left: -158, top: -48 },
  );
  assert.deepEqual(
    resolveContextSubmenuPosition(
      { width: 180, right: 570, top: 20 },
      { width: 160, height: 500 },
      { width: 600, height: 420 },
    ),
    { left: -158, top: -12 },
  );
});

test('context menu key resolver maps supported keys and ignores composition', () => {
  const mappings: Array<[string, ContextMenuKeyAction]> = [
    ['Escape', 'close'],
    ['ArrowDown', 'highlight-next'],
    ['j', 'highlight-next'],
    ['ArrowUp', 'highlight-previous'],
    ['k', 'highlight-previous'],
    ['Enter', 'select-highlighted'],
    ['Tab', 'trap-focus'],
  ];

  for (const [key, action] of mappings) {
    assert.equal(resolveContextMenuKeyAction({ key }), action);
  }

  assert.equal(resolveContextMenuKeyAction({ key: 'x' }), null);
  assert.equal(resolveContextMenuKeyAction({ key: 'Enter', isComposing: true }), null);
});

test('context menu highlight index wraps and stays inert for an empty actionable list', () => {
  assert.equal(resolveNextContextMenuHighlightIndex(-1, 3, 'next'), 0);
  assert.equal(resolveNextContextMenuHighlightIndex(2, 3, 'next'), 0);
  assert.equal(resolveNextContextMenuHighlightIndex(-1, 3, 'previous'), 2);
  assert.equal(resolveNextContextMenuHighlightIndex(0, 3, 'previous'), 2);
  assert.equal(resolveNextContextMenuHighlightIndex(0, 0, 'next'), -1);
  assert.equal(resolveNextContextMenuHighlightIndex(0, 0, 'previous'), -1);
});

test('context menu action runner preserves close isolation and selection behavior', () => {
  const calls: string[] = [];
  let highlightIndex = 1;
  const event = buildKeyEvent('Escape', {
    preventDefault: () => calls.push('prevent'),
    stopImmediatePropagation: () => calls.push('stop-immediate'),
    stopPropagation: () => calls.push('stop'),
  });
  const deps = {
    getActionableItemCount: () => 3,
    getHighlightedItem: () => ({ hasSubmenu: false, onSelect: () => calls.push('select') }),
    setHighlightIndex: (updater: (previousIndex: number) => number) => {
      highlightIndex = updater(highlightIndex);
      calls.push(`highlight:${highlightIndex}`);
    },
    onClose: () => calls.push('close'),
  };

  runContextMenuKeyAction('close', event, deps);
  runContextMenuKeyAction('highlight-next', buildKeyEvent('ArrowDown'), deps);
  runContextMenuKeyAction('highlight-previous', buildKeyEvent('ArrowUp'), deps);
  runContextMenuKeyAction('select-highlighted', buildKeyEvent('Enter'), deps);
  runContextMenuKeyAction('trap-focus', buildKeyEvent('Tab'), deps);

  assert.deepEqual(calls, [
    'prevent',
    'stop',
    'stop-immediate',
    'close',
    'highlight:2',
    'highlight:1',
    'select',
    'close',
    'close',
  ]);
});

test('context menu keyboard actions move DOM focus with the roving highlight', () => {
  const calls: string[] = [];
  let highlightIndex = 1;
  let submenuHighlightIndex = 0;
  const deps = {
    getActionableItemCount: () => 3,
    getHighlightIndex: () => highlightIndex,
    getHighlightedItem: () => ({ hasSubmenu: true }),
    setHighlightIndex: (updater: (previousIndex: number) => number) => {
      highlightIndex = updater(highlightIndex);
      calls.push(`highlight:${highlightIndex}`);
    },
    focusItemAtIndex: (index: number) => calls.push(`focus:${index}`),
    onClose: () => calls.push('close'),
    getSubmenuItemCount: () => 2,
    getSubmenuHighlightIndex: () => submenuHighlightIndex,
    getSubmenuHighlightedItem: () => ({ hasSubmenu: false }),
    setSubmenuHighlightIndex: (updater: (previousIndex: number) => number) => {
      submenuHighlightIndex = updater(submenuHighlightIndex);
      calls.push(`submenu-highlight:${submenuHighlightIndex}`);
    },
    focusSubmenuItemAtIndex: (index: number) => calls.push(`submenu-focus:${index}`),
    openHighlightedSubmenu: () => calls.push('open-submenu'),
    closeSubmenu: () => calls.push('close-submenu'),
  };

  runContextMenuKeyAction('highlight-next', buildKeyEvent('ArrowDown'), deps);
  runContextMenuKeyAction('highlight-previous', buildKeyEvent('ArrowUp'), deps);
  runContextMenuKeyAction('open-submenu', buildKeyEvent('ArrowRight'), deps);
  runContextMenuKeyAction('submenu-next', buildKeyEvent('ArrowDown'), deps);
  runContextMenuKeyAction('close-submenu', buildKeyEvent('ArrowLeft'), deps);

  assert.deepEqual(calls, [
    'highlight:2',
    'focus:2',
    'highlight:1',
    'focus:1',
    'open-submenu',
    'submenu-highlight:0',
    'submenu-focus:0',
    'submenu-highlight:1',
    'submenu-focus:1',
    'close-submenu',
    'focus:1',
  ]);
});

test('context menu Tab close preserves the browser tab order', () => {
  const calls: string[] = [];

  runContextMenuKeyAction('trap-focus', buildKeyEvent('Tab', {
    preventDefault: () => calls.push('prevent'),
    stopImmediatePropagation: () => calls.push('stop-immediate'),
    stopPropagation: () => calls.push('stop'),
  }), {
    getActionableItemCount: () => 1,
    getHighlightedItem: () => ({ hasSubmenu: false }),
    setHighlightIndex: () => calls.push('highlight'),
    onClose: () => calls.push('close'),
  });

  assert.deepEqual(calls, ['close']);
});

test('context menu action runner does not select submenu or missing highlighted items', () => {
  const calls: string[] = [];
  const baseDeps = {
    getActionableItemCount: () => 1,
    setHighlightIndex: () => calls.push('highlight'),
    onClose: () => calls.push('close'),
  };

  runContextMenuKeyAction('select-highlighted', buildKeyEvent('Enter'), {
    ...baseDeps,
    getHighlightedItem: () => ({ hasSubmenu: true, onSelect: () => calls.push('select-submenu') }),
  });
  runContextMenuKeyAction('select-highlighted', buildKeyEvent('Enter'), {
    ...baseDeps,
    getHighlightedItem: () => undefined,
  });

  assert.deepEqual(calls, []);
});

test('context menu keyboard runtime installs a capture listener through the adapter and cleans up', () => {
  const calls: string[] = [];
  let listener: ((event: KeyboardEvent) => void) | undefined;
  let highlightIndex = -1;

  const cleanup = installContextMenuKeyboardRuntime({
    addWindowKeydownListener: (nextListener) => {
      listener = nextListener;
      return () => {
        listener = undefined;
        calls.push('cleanup');
      };
    },
    getActionableItemCount: () => 2,
    getHighlightedItem: () => ({ hasSubmenu: false, onSelect: () => calls.push('select') }),
    setHighlightIndex: (updater) => {
      highlightIndex = updater(highlightIndex);
      calls.push(`highlight:${highlightIndex}`);
    },
    onClose: () => calls.push('close'),
  });

  listener?.(buildKeyEvent('ArrowDown') as KeyboardEvent);
  listener?.(buildKeyEvent('Enter') as KeyboardEvent);
  listener?.(buildKeyEvent('x') as KeyboardEvent);
  cleanup();

  assert.deepEqual(calls, ['highlight:0', 'select', 'close', 'cleanup']);
  assert.equal(listener, undefined);
});

test('context menu keyboard runtime is inert without a window keydown host', () => {
  const cleanup = installContextMenuKeyboardRuntime({
    addWindowKeydownListener: null,
    getActionableItemCount: () => 1,
    getHighlightedItem: () => ({ hasSubmenu: false }),
    setHighlightIndex: () => {
      throw new Error('highlight should not run without an installed listener');
    },
    onClose: () => {
      throw new Error('close should not run without an installed listener');
    },
  });

  cleanup();
});

test('context menu component delegates positioning and keydown handling to runtime helpers', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/context-menu/ContextMenu.tsx'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*installContextMenuKeyboardRuntime,[\s\S]*resolveContextMenuPosition,[\s\S]*resolveContextSubmenuPosition,[\s\S]*\} from '\.\/ContextMenu\.runtime';/s,
  );
  assert.match(source, /setClamped\(resolveContextSubmenuPosition\(/);
  assert.match(source, /setPos\(resolveContextMenuPosition\(/);
  assert.match(
    source,
    /return installContextMenuKeyboardRuntime\(\{[\s\S]*addWindowKeydownListener: typeof window === 'undefined'[\s\S]*window\.addEventListener\('keydown', listener, true\);[\s\S]*getActionableItemCount:[\s\S]*getHighlightIndex:[\s\S]*getHighlightedItem:[\s\S]*setHighlightIndex: setRovingHighlightIdx,[\s\S]*focusItemAtIndex:[\s\S]*onClose,/s,
  );
  assert.doesNotMatch(source, /const handleKey = \(e: KeyboardEvent\) => \{/);
  assert.doesNotMatch(source, /function clampPosition/);
});

test('context menu component wires roving DOM focus to main and submenu items', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/context-menu/ContextMenu.tsx'),
    'utf8',
  );

  assert.match(
    source,
    /const menuItemRefs = useRef<\(HTMLButtonElement \| null\)\[\]>\(\[\]\);/,
    'main menu actionable items should register DOM refs for roving focus',
  );
  assert.match(
    source,
    /const submenuItemRefs = useRef<\(HTMLButtonElement \| null\)\[\]>\(\[\]\);/,
    'submenu actionable items should register DOM refs for roving focus',
  );
  assert.match(
    source,
    /ref=\{buttonRef\}[\s\S]*tabIndex=\{tabIndex\}/,
    'ContextMenu rows should expose the roving tabIndex on the real menuitem button',
  );
  assert.match(
    source,
    /ref=\{menuRef\}[\s\S]*role="menu"[\s\S]*tabIndex=\{-1\}/,
    'the menu container should be programmatically focusable as an empty-menu fallback',
  );
  assert.match(
    source,
    /focusItemAtIndex: \(index\) => \{[\s\S]*menuItemRefs\.current\[index\]\?\.focus\(\);[\s\S]*\}/,
    'main-menu keyboard navigation should move real DOM focus to the highlighted item',
  );
  assert.match(
    source,
    /focusSubmenuItemAtIndex: \(index\) => \{[\s\S]*submenuItemRefs\.current\[index\]\?\.focus\(\);[\s\S]*\}/,
    'submenu keyboard navigation should move real DOM focus to the highlighted child item',
  );
});
