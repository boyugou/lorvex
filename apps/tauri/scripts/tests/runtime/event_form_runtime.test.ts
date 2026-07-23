import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  installEventFormEscapeRuntime,
  shouldCancelEventFormFromKey,
} from '../../../app/src/components/calendar/event-form/EventForm.runtime';

class FakeNode {
  constructor(private readonly children: FakeNode[] = []) {}

  contains(target: unknown): boolean {
    return target === this || this.children.includes(target as FakeNode);
  }
}

test('event form Escape predicate ignores non-Escape and composing Escape events', () => {
  assert.equal(shouldCancelEventFormFromKey({ key: 'Escape', isComposing: false, defaultPrevented: false }), true);
  assert.equal(shouldCancelEventFormFromKey({ key: 'Escape', isComposing: true, defaultPrevented: false }), false);
  assert.equal(shouldCancelEventFormFromKey({ key: 'Enter', isComposing: false, defaultPrevented: false }), false);
});

test('event form Escape runtime cancels through the latest callback and unregisters cleanup', () => {
  let listener: EventListener | undefined;
  let currentCancel = () => calls.push('cancel-old');
  const calls: string[] = [];
  const inside = new FakeNode();
  const root = new FakeNode([inside]);

  const cleanup = installEventFormEscapeRuntime({
    documentTarget: {
      addEventListener: (type, nextListener) => {
        assert.equal(type, 'keydown');
        listener = nextListener as EventListener;
      },
      removeEventListener: (type, nextListener) => {
        assert.equal(type, 'keydown');
        if (listener === nextListener) {
          listener = undefined;
          calls.push('cleanup');
        }
      },
    },
    getFormRoot: () => root as unknown as HTMLElement,
    getOnCancel: () => currentCancel,
  });

  currentCancel = () => calls.push('cancel-new');
  listener?.({
    key: 'Escape',
    isComposing: false,
    defaultPrevented: false,
    target: inside,
    preventDefault: () => calls.push('prevent'),
  } as KeyboardEvent);
  listener?.({
    key: 'Escape',
    isComposing: true,
    defaultPrevented: false,
    target: inside,
    preventDefault: () => calls.push('prevent-composing'),
  } as KeyboardEvent);
  listener?.({
    key: 'Enter',
    isComposing: false,
    defaultPrevented: false,
    target: inside,
    preventDefault: () => calls.push('prevent-enter'),
  } as KeyboardEvent);
  cleanup();

  assert.deepEqual(calls, ['prevent', 'cancel-new', 'cleanup']);
  assert.equal(listener, undefined);
});

test('event form Escape runtime is a no-op without a document target', () => {
  const calls: string[] = [];

  const cleanup = installEventFormEscapeRuntime({
    documentTarget: undefined,
    getFormRoot: () => null,
    getOnCancel: () => () => calls.push('cancel'),
  });

  cleanup();

  assert.deepEqual(calls, []);
});

test('event form component delegates Escape wiring to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/calendar/event-form/EventForm.tsx'),
    'utf8',
  );

  assert.match(
    source,
    /import \{ installEventFormEscapeRuntime \} from '\.\/EventForm\.runtime';/,
  );
  assert.match(source, /return installEventFormEscapeRuntime\(\{/);
  assert.match(source, /documentTarget: document,/);
  assert.match(source, /getFormRoot: \(\) => formRef\.current,/);
  assert.match(source, /getOnCancel: \(\) => onCancelRef\.current,/);
  assert.doesNotMatch(source, /const handleKeyDown = \(e: KeyboardEvent\) => \{/);
  assert.doesNotMatch(source, /document\.addEventListener\('keydown', handleKeyDown\)/);
});
