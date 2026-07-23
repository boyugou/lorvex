import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  installKeyboardShortcutsPanelCloseRuntime,
  shouldCloseKeyboardShortcutsPanelFromEvent,
} from '../../../app/src/components/keyboard-shortcuts/KeyboardShortcutsPanel.runtime';

function buildKeyboardEvent(overrides: Partial<KeyboardEvent> = {}): KeyboardEvent {
  return {
    altKey: false,
    ctrlKey: false,
    key: '?',
    metaKey: false,
    preventDefault() {},
    target: null,
    ...overrides,
  } as KeyboardEvent;
}

test('keyboard shortcuts panel close predicate accepts only bare question mark outside editable targets', () => {
  const editableTarget = new EventTarget();
  const isEditableTarget = (target: EventTarget | null) => target === editableTarget;

  assert.equal(
    shouldCloseKeyboardShortcutsPanelFromEvent(buildKeyboardEvent(), isEditableTarget),
    true,
  );
  assert.equal(
    shouldCloseKeyboardShortcutsPanelFromEvent(buildKeyboardEvent({ key: 'Escape' }), isEditableTarget),
    false,
  );
  assert.equal(
    shouldCloseKeyboardShortcutsPanelFromEvent(buildKeyboardEvent({ metaKey: true }), isEditableTarget),
    false,
  );
  assert.equal(
    shouldCloseKeyboardShortcutsPanelFromEvent(buildKeyboardEvent({ ctrlKey: true }), isEditableTarget),
    false,
  );
  assert.equal(
    shouldCloseKeyboardShortcutsPanelFromEvent(buildKeyboardEvent({ altKey: true }), isEditableTarget),
    false,
  );
  assert.equal(
    shouldCloseKeyboardShortcutsPanelFromEvent(
      buildKeyboardEvent({ target: editableTarget }),
      isEditableTarget,
    ),
    false,
  );
});

test('keyboard shortcuts panel close runtime prevents default and closes on bare question mark', () => {
  const calls: string[] = [];
  let listener: ((event: KeyboardEvent) => void) | null = null;
  const cleanup = installKeyboardShortcutsPanelCloseRuntime({
    addWindowKeydownListener: (nextListener) => {
      listener = nextListener;
      return () => {
        listener = null;
        calls.push('cleanup');
      };
    },
    isEditableTarget: () => false,
    onClose: () => {
      calls.push('close');
    },
  });

  listener?.(buildKeyboardEvent({
    preventDefault: () => {
      calls.push('prevent');
    },
  }));
  cleanup();

  assert.deepEqual(calls, ['prevent', 'close', 'cleanup']);
  assert.equal(listener, null);
});

test('keyboard shortcuts panel close runtime ignores non-matching key events', () => {
  const calls: string[] = [];
  let listener: ((event: KeyboardEvent) => void) | null = null;
  installKeyboardShortcutsPanelCloseRuntime({
    addWindowKeydownListener: (nextListener) => {
      listener = nextListener;
      return () => {};
    },
    isEditableTarget: () => false,
    onClose: () => {
      calls.push('close');
    },
  });

  listener?.(buildKeyboardEvent({
    key: '/',
    preventDefault: () => {
      calls.push('prevent');
    },
  }));

  assert.deepEqual(calls, []);
});

test('keyboard shortcuts panel close runtime is inert without a window keydown host', () => {
  const cleanup = installKeyboardShortcutsPanelCloseRuntime({
    addWindowKeydownListener: null,
    isEditableTarget: () => false,
    onClose: () => {
      throw new Error('close should not be called without an installed listener');
    },
  });

  cleanup();
});

test('keyboard shortcuts panel component delegates keydown handling to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/keyboard-shortcuts/KeyboardShortcutsPanel.tsx'),
    'utf8',
  );

  assert.match(
    source,
    /import \{ installKeyboardShortcutsPanelCloseRuntime \} from '\.\/KeyboardShortcutsPanel\.runtime';/,
  );
  assert.match(
    source,
    /return installKeyboardShortcutsPanelCloseRuntime\(\{[\s\S]*addWindowKeydownListener: typeof window === 'undefined'[\s\S]*window\.addEventListener\('keydown', listener\);[\s\S]*isEditableTarget,[\s\S]*onClose,/s,
  );
  assert.doesNotMatch(source, /const handleKeyDown = \(event: KeyboardEvent\) => \{/);
});

test('keyboard shortcuts panel layout remains responsive for narrow translated labels', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/keyboard-shortcuts/KeyboardShortcutsPanel.tsx'),
    'utf8',
  );

  assert.match(
    source,
    /className="grid grid-cols-1[^"]*sm:grid-cols-2/,
    'shortcut groups should use one column by default and only split when the viewport allows it',
  );
  assert.match(
    source,
    /className="flex items-center justify-between gap-[^"]*min-w-0/,
    'shortcut rows need gap and min-w-0 so translated labels can shrink before keycaps',
  );
  assert.match(
    source,
    /className="text-text-secondary text-sm min-w-0 flex-1 break-words/,
    'shortcut labels need an explicit wrapping policy for long translations',
  );
  assert.match(
    source,
    /<kbd className="[^"]*shrink-0/,
    'shortcut keycaps must not shrink when labels wrap',
  );
  assert.match(
    source,
    /<h2 className="text-text-primary text-lg font-light min-w-0 flex-1 break-words">/,
    'shortcut panel header title needs the same i18n wrapping guard as row labels',
  );
  assert.match(
    source,
    /<button[\s\S]*className="text-text-muted[^"]*shrink-0/,
    'shortcut panel close button must not shrink when the translated title wraps',
  );
});
