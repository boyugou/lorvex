import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

import { announce, resetAnnouncerIdsForTests, subscribeAnnouncer } from '../../../app/src/lib/announce';
import {
  AnnouncementLiveRegion,
} from '../../../app/src/components/ui/Announcer';
import {
  ANNOUNCEMENT_DEQUEUE_DELAY_MS,
  createBrowserAnnouncerTimerHost,
  dequeueAnnouncementEntry,
  enqueueAnnouncementEntry,
  scheduleAnnouncementDequeue,
  type AnnouncerTimerHost,
} from '../../../app/src/components/ui/Announcer.runtime';
import {
  collectModalTabScopeRootsFromBodyChildren,
  registerGlobalModalEscapeListener,
  registerGlobalModalTabListener,
  recoverTopModalFocusWhenBodyActive,
  scheduleGlobalModalEscapeClose,
  shouldDismissModalFromBackdropClick,
} from '../../../app/src/components/ui/overlay/ModalShell';
import { hexWithAlpha } from '../../../app/src/lib/colorUtils';
import {
  resetClientErrorLogDedupeForTests,
  reportClientError,
  setAppendErrorLogForTests,
} from '../../../app/src/lib/errors/errorLogging';
import { trapTabFocusWithin } from '../../../app/src/lib/focus/focusTrap';
import { createBrowserFocusTrapHost } from '../../../app/src/lib/focus/focusTrap.runtime';
import { parseString } from '../../../app/src/lib/query/usePreference.logic';

test('reportClientError does not suppress repeated fallback logging when append_error_log itself keeps failing', async () => {
  resetClientErrorLogDedupeForTests();
  setAppendErrorLogForTests(async () => {
    throw new Error('append failed');
  });

  const originalConsoleError = console.error;
  const calls: Array<{ message: string; payload: unknown }> = [];
  console.error = (message?: unknown, payload?: unknown) => {
    calls.push({
      message: String(message ?? ''),
      payload,
    });
  };

  try {
    reportClientError('runtime.test', 'Repeated logging failure', new Error('boom'));
    reportClientError('runtime.test', 'Repeated logging failure', new Error('boom'));
    await new Promise((resolve) => setTimeout(resolve, 0));
  } finally {
    console.error = originalConsoleError;
    setAppendErrorLogForTests(null);
    resetClientErrorLogDedupeForTests();
  }

  assert.equal(calls.length, 2);
  assert.match(calls[0]?.message ?? '', /\[client-error-log:runtime\.test\]/);
  assert.match(calls[1]?.message ?? '', /\[client-error-log:runtime\.test\]/);
});

test('reportClientError still dedupes same-tick successful writes while the first append is in flight', async () => {
  resetClientErrorLogDedupeForTests();
  let appendCalls = 0;
  setAppendErrorLogForTests(async () => {
    appendCalls += 1;
  });

  try {
    reportClientError('runtime.test', 'Deduped success path');
    reportClientError('runtime.test', 'Deduped success path');
    await new Promise((resolve) => setTimeout(resolve, 0));
  } finally {
    setAppendErrorLogForTests(null);
    resetClientErrorLogDedupeForTests();
  }

  assert.equal(appendCalls, 1);
});

test('reportClientError schedules a follow-up write when a slow successful append spans past the dedupe window', async () => {
  resetClientErrorLogDedupeForTests();
  let appendCalls = 0;
  let resolveFirstAppend: (() => void) | null = null;
  setAppendErrorLogForTests(async () => {
    appendCalls += 1;
    if (appendCalls === 1) {
      await new Promise<void>((resolve) => {
        resolveFirstAppend = resolve;
      });
    }
  });

  const originalDateNow = Date.now;
  let now = 0;
  Date.now = () => now;

  try {
    reportClientError('runtime.test', 'Slow success path');
    now = 6_000;
    reportClientError('runtime.test', 'Slow success path');
    resolveFirstAppend?.();
    await new Promise((resolve) => setTimeout(resolve, 0));
    await new Promise((resolve) => setTimeout(resolve, 0));
  } finally {
    Date.now = originalDateNow;
    setAppendErrorLogForTests(null);
    resetClientErrorLogDedupeForTests();
  }

  assert.equal(appendCalls, 2);
});

test('reportClientError drains every queued retry when repeated identical failures pile up behind one inflight append', async () => {
  resetClientErrorLogDedupeForTests();
  setAppendErrorLogForTests(async () => {
    throw new Error('append failed');
  });

  const originalConsoleError = console.error;
  const calls: string[] = [];
  console.error = (message?: unknown) => {
    calls.push(String(message ?? ''));
  };

  try {
    reportClientError('runtime.test', 'Burst logging failure', new Error('boom'));
    reportClientError('runtime.test', 'Burst logging failure', new Error('boom'));
    reportClientError('runtime.test', 'Burst logging failure', new Error('boom'));
    await new Promise((resolve) => setTimeout(resolve, 0));
    await new Promise((resolve) => setTimeout(resolve, 0));
    await new Promise((resolve) => setTimeout(resolve, 0));
  } finally {
    console.error = originalConsoleError;
    setAppendErrorLogForTests(null);
    resetClientErrorLogDedupeForTests();
  }

  assert.equal(calls.length, 3);
});

test('announce emits distinct entries for repeated identical messages', () => {
  resetAnnouncerIdsForTests();
  const seen: Array<{ id: number; message: string; priority: 'polite' | 'assertive' }> = [];
  const unsubscribe = subscribeAnnouncer((entry) => {
    seen.push(entry);
  });

  try {
    announce('Same message');
    announce('Same message');
  } finally {
    unsubscribe();
    resetAnnouncerIdsForTests();
  }

  assert.deepEqual(
    seen.map((entry) => ({ message: entry.message, priority: entry.priority })),
    [
      { message: 'Same message', priority: 'polite' },
      { message: 'Same message', priority: 'polite' },
    ],
  );
  assert.notEqual(seen[0]?.id, seen[1]?.id);
});

test('AnnouncementLiveRegion markup changes for repeated identical messages so the live region is mutated', () => {
  const first = renderToStaticMarkup(
    createElement(AnnouncementLiveRegion, {
      entry: { id: 1, message: 'Same message', priority: 'polite' },
      role: 'status',
      priority: 'polite',
    }),
  );
  const second = renderToStaticMarkup(
    createElement(AnnouncementLiveRegion, {
      entry: { id: 2, message: 'Same message', priority: 'polite' },
      role: 'status',
      priority: 'polite',
    }),
  );

  assert.notEqual(first, second);
  assert.match(first, /data-announcement-seq="1"/);
  assert.match(second, /data-announcement-seq="2"/);
  assert.match(first, />Same message</);
  assert.match(second, />Same message</);
});

test('announcement queue preserves back-to-back same-priority entries instead of letting the later one overwrite the earlier one', () => {
  const first = { id: 1, message: 'First', priority: 'polite' as const };
  const second = { id: 2, message: 'Second', priority: 'polite' as const };

  const queued = enqueueAnnouncementEntry(enqueueAnnouncementEntry([], first), second);
  assert.deepEqual(
    queued.map((entry) => entry.id),
    [1, 2],
  );
  assert.deepEqual(
    dequeueAnnouncementEntry(queued).map((entry) => entry.id),
    [2],
  );
});

test('announcement dequeue scheduling uses the injected timer host', () => {
  const callbacks: Array<() => void> = [];
  const clearedHandles: unknown[] = [];
  const delays: number[] = [];
  const host: AnnouncerTimerHost = {
    clearTimeout: (handle) => {
      clearedHandles.push(handle);
    },
    setTimeout: (callback, delayMs) => {
      callbacks.push(callback);
      delays.push(delayMs);
      return `announcer-timer-${callbacks.length}`;
    },
  };

  let dequeueCount = 0;
  const cleanup = scheduleAnnouncementDequeue(host, () => {
    dequeueCount += 1;
  });

  assert.deepEqual(delays, [ANNOUNCEMENT_DEQUEUE_DELAY_MS]);
  assert.equal(dequeueCount, 0);

  callbacks[0]?.();
  assert.equal(dequeueCount, 1);

  cleanup();
  assert.deepEqual(clearedHandles, ['announcer-timer-1']);
});

test('announcer component delegates browser timer wiring to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/ui/Announcer.tsx'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/ui/Announcer.runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserAnnouncerTimerHost,[\s\S]*dequeueAnnouncementEntry,[\s\S]*enqueueAnnouncementEntry,[\s\S]*scheduleAnnouncementDequeue,[\s\S]*\} from '\.\/Announcer\.runtime';/s,
  );
  assert.match(source, /const announcerTimerHost = createBrowserAnnouncerTimerHost\(\);/);
  assert.match(
    source,
    /function useAnnouncementDequeueTimer\([\s\S]*setQueue: React\.Dispatch<React\.SetStateAction<AnnouncementEntry\[]>>,[\s\S]*return scheduleAnnouncementDequeue\([\s\S]*announcerTimerHost,[\s\S]*\(\) => setQueue\(\(queue\) => dequeueAnnouncementEntry\(queue\)\),[\s\S]*\);/s,
  );
  assert.match(
    source,
    /useAnnouncementDequeueTimer\(polite, setPoliteQueue\);[\s\S]*useAnnouncementDequeueTimer\(assertive, setAssertiveQueue\);/s,
  );
  assert.doesNotMatch(source, /(?<!\.)\bsetTimeout\(/);
  assert.doesNotMatch(source, /(?<!\.)\bclearTimeout\(/);

  assert.match(runtimeSource, /export function createBrowserAnnouncerTimerHost\(\): AnnouncerTimerHost/);
  assert.match(runtimeSource, /globalThis\.clearTimeout\(handle as ReturnType<typeof globalThis\.setTimeout>\);/);
  assert.match(runtimeSource, /setTimeout: \(callback, delayMs\) => globalThis\.setTimeout\(callback, delayMs\),/);
});

test('announcer runtime owns the browser timer host wiring', () => {
  const host = createBrowserAnnouncerTimerHost();
  assert.equal(typeof host.setTimeout, 'function');
  assert.equal(typeof host.clearTimeout, 'function');
});

test('focus trap facade delegates DOM host access through the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/focus/focusTrap.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserFocusTrapHost,[\s\S]*trapTabFocusWithinRuntime,[\s\S]*\} from '\.\/focusTrap\.runtime';/s,
  );
  assert.match(source, /const browserFocusTrapHost = createBrowserFocusTrapHost\(\);/);
  assert.match(
    source,
    /return trapTabFocusWithinRuntime\(browserFocusTrapHost, container, event, options\);/,
  );
  assert.doesNotMatch(source, /typeof window|window\.|typeof document|document\.|typeof HTMLElement/);
});

test('focus trap runtime owns the browser element and style host wiring', () => {
  class FakeHTMLElement {}
  const button = new FakeHTMLElement();
  const originalWindow = globalThis.window;
  const originalDocument = globalThis.document;
  const originalHTMLElement = globalThis.HTMLElement;

  Object.defineProperty(globalThis, 'window', {
    configurable: true,
    value: {
      getComputedStyle: (element: unknown) => {
        assert.equal(element, button);
        return { display: 'block', visibility: 'visible' };
      },
    },
  });
  Object.defineProperty(globalThis, 'document', {
    configurable: true,
    value: {
      activeElement: button,
    },
  });
  Object.defineProperty(globalThis, 'HTMLElement', {
    configurable: true,
    value: FakeHTMLElement,
  });

  try {
    const host = createBrowserFocusTrapHost();

    assert.equal(host.getActiveElement(), button);
    assert.equal(host.getElementConstructor(), FakeHTMLElement);
    assert.deepEqual(host.getComputedStyle(button as unknown as HTMLElement), {
      display: 'block',
      visibility: 'visible',
    });
  } finally {
    Object.defineProperty(globalThis, 'window', { configurable: true, value: originalWindow });
    Object.defineProperty(globalThis, 'document', { configurable: true, value: originalDocument });
    Object.defineProperty(globalThis, 'HTMLElement', { configurable: true, value: originalHTMLElement });
  }
});

test('trapTabFocusWithin skips visibility-hidden controls when cycling focus', () => {
  class FakeHTMLElement {
    focusCalled = 0;
    constructor(
      private readonly hidden: boolean,
      private readonly focusable: boolean = true,
    ) {}
    hasAttribute(_name: string): boolean {
      return false;
    }
    getAttribute(_name: string): string | null {
      return null;
    }
    tabIndex = 0;
    getClientRects(): DOMRectList {
      return [{ width: 10 }] as unknown as DOMRectList;
    }
    focus(): void {
      this.focusCalled += 1;
    }
    isHidden(): boolean {
      return this.hidden;
    }
    matches(_selector: string): boolean {
      return this.focusable;
    }
    querySelectorAll(): FakeHTMLElement[] {
      return [];
    }
  }

  const hiddenButton = new FakeHTMLElement(true);
  const visibleButton = new FakeHTMLElement(false);
  const containerRoot = new FakeHTMLElement(false, false);
  containerRoot.querySelectorAll = () => [hiddenButton, visibleButton];

  const originalWindow = globalThis.window;
  const originalDocument = globalThis.document;
  const originalHTMLElement = globalThis.HTMLElement;
  Object.defineProperty(globalThis, 'window', {
    configurable: true,
    value: {
      getComputedStyle: (element: unknown) => ({
        display: 'block',
        visibility: element instanceof FakeHTMLElement && element.isHidden() ? 'hidden' : 'visible',
      }),
    },
  });
  Object.defineProperty(globalThis, 'document', {
    configurable: true,
    value: {
      activeElement: visibleButton,
    },
  });
  Object.defineProperty(globalThis, 'HTMLElement', {
    configurable: true,
    value: FakeHTMLElement,
  });

  try {
    const trapped = trapTabFocusWithin(
      containerRoot as unknown as HTMLElement,
      {
        key: 'Tab',
        shiftKey: false,
        defaultPrevented: false,
        prevented: false,
        preventDefault() {
          this.prevented = true;
        },
      },
    );

    assert.equal(trapped, true);
    assert.equal(hiddenButton.focusCalled, 0);
    assert.equal(visibleButton.focusCalled, 1);
  } finally {
    Object.defineProperty(globalThis, 'window', { configurable: true, value: originalWindow });
    Object.defineProperty(globalThis, 'document', { configurable: true, value: originalDocument });
    Object.defineProperty(globalThis, 'HTMLElement', { configurable: true, value: originalHTMLElement });
  }
});

test('trapTabFocusWithin includes modal-owned portal roots in the tab scope so focus wraps instead of escaping', () => {
  class FakeHTMLElement {
    focusCalled = 0;
    constructor(private readonly focusable: boolean = true) {}
    hasAttribute(_name: string): boolean {
      return false;
    }
    getAttribute(_name: string): string | null {
      return null;
    }
    tabIndex = 0;
    getClientRects(): DOMRectList {
      return [{ width: 10 }] as unknown as DOMRectList;
    }
    focus(): void {
      this.focusCalled += 1;
    }
    matches(_selector: string): boolean {
      return this.focusable;
    }
    querySelectorAll(): FakeHTMLElement[] {
      return [];
    }
  }

  const insideButton = new FakeHTMLElement();
  const portalButton = new FakeHTMLElement();
  const containerRoot = new FakeHTMLElement(false);
  containerRoot.querySelectorAll = () => [insideButton];
  const portalRoot = new FakeHTMLElement(false);
  portalRoot.querySelectorAll = () => [portalButton];

  const originalWindow = globalThis.window;
  const originalDocument = globalThis.document;
  const originalHTMLElement = globalThis.HTMLElement;
  Object.defineProperty(globalThis, 'window', {
    configurable: true,
    value: {
      getComputedStyle: () => ({
        display: 'block',
        visibility: 'visible',
      }),
    },
  });
  Object.defineProperty(globalThis, 'document', {
    configurable: true,
    value: {
      activeElement: portalButton,
    },
  });
  Object.defineProperty(globalThis, 'HTMLElement', {
    configurable: true,
    value: FakeHTMLElement,
  });

  try {
    const event = {
      key: 'Tab',
      shiftKey: false,
      defaultPrevented: false,
      prevented: false,
      preventDefault() {
        this.prevented = true;
      },
    };
    const trapped = trapTabFocusWithin(
      containerRoot as unknown as HTMLElement,
      event,
      {
        extraRoots: [portalRoot as unknown as HTMLElement],
      },
    );

    assert.equal(trapped, true);
    assert.equal(event.prevented, true);
    assert.equal(insideButton.focusCalled, 1);
  } finally {
    Object.defineProperty(globalThis, 'window', { configurable: true, value: originalWindow });
    Object.defineProperty(globalThis, 'document', { configurable: true, value: originalDocument });
    Object.defineProperty(globalThis, 'HTMLElement', { configurable: true, value: originalHTMLElement });
  }
});

test('trapTabFocusWithin stays inert when DOM element constructors are unavailable', () => {
  const originalHTMLElement = globalThis.HTMLElement;
  Reflect.deleteProperty(globalThis, 'HTMLElement');

  try {
    const event = {
      key: 'Tab',
      shiftKey: false,
      defaultPrevented: false,
      prevented: false,
      preventDefault() {
        this.prevented = true;
      },
    };

    assert.equal(trapTabFocusWithin(null, event), false);
    assert.equal(event.prevented, false);
  } finally {
    if (originalHTMLElement === undefined) {
      Reflect.deleteProperty(globalThis, 'HTMLElement');
    } else {
      globalThis.HTMLElement = originalHTMLElement;
    }
  }
});

test('trapTabFocusWithin stays inert when computed style is unavailable', () => {
  class FakeHTMLElement {
    focusCalled = 0;
    hasAttribute(_name: string): boolean {
      return false;
    }
    getAttribute(_name: string): string | null {
      return null;
    }
    tabIndex = 0;
    getClientRects(): DOMRectList {
      return [{ width: 10 }] as unknown as DOMRectList;
    }
    focus(): void {
      this.focusCalled += 1;
    }
    matches(_selector: string): boolean {
      return true;
    }
    querySelectorAll(): FakeHTMLElement[] {
      return [];
    }
  }

  const root = new FakeHTMLElement();
  const originalWindow = globalThis.window;
  const originalHTMLElement = globalThis.HTMLElement;
  Object.defineProperty(globalThis, 'window', {
    configurable: true,
    value: undefined,
  });
  Object.defineProperty(globalThis, 'HTMLElement', {
    configurable: true,
    value: FakeHTMLElement,
  });

  try {
    const event = {
      key: 'Tab',
      shiftKey: false,
      defaultPrevented: false,
      prevented: false,
      preventDefault() {
        this.prevented = true;
      },
    };

    assert.equal(trapTabFocusWithin(root as unknown as HTMLElement, event), false);
    assert.equal(event.prevented, false);
    assert.equal(root.focusCalled, 0);
  } finally {
    Object.defineProperty(globalThis, 'window', { configurable: true, value: originalWindow });
    Object.defineProperty(globalThis, 'HTMLElement', { configurable: true, value: originalHTMLElement });
  }
});

test('trapTabFocusWithin treats missing active document as outside the trap', () => {
  class FakeHTMLElement {
    focusCalled = 0;
    hasAttribute(_name: string): boolean {
      return false;
    }
    getAttribute(_name: string): string | null {
      return null;
    }
    tabIndex = 0;
    getClientRects(): DOMRectList {
      return [{ width: 10 }] as unknown as DOMRectList;
    }
    focus(): void {
      this.focusCalled += 1;
    }
    matches(_selector: string): boolean {
      return true;
    }
    querySelectorAll(): FakeHTMLElement[] {
      return [];
    }
  }

  const root = new FakeHTMLElement();
  const originalWindow = globalThis.window;
  const originalDocument = globalThis.document;
  const originalHTMLElement = globalThis.HTMLElement;
  Object.defineProperty(globalThis, 'window', {
    configurable: true,
    value: {
      getComputedStyle: () => ({
        display: 'block',
        visibility: 'visible',
      }),
    },
  });
  Object.defineProperty(globalThis, 'document', {
    configurable: true,
    value: undefined,
  });
  Object.defineProperty(globalThis, 'HTMLElement', {
    configurable: true,
    value: FakeHTMLElement,
  });

  try {
    const event = {
      key: 'Tab',
      shiftKey: false,
      defaultPrevented: false,
      prevented: false,
      preventDefault() {
        this.prevented = true;
      },
    };

    assert.equal(trapTabFocusWithin(root as unknown as HTMLElement, event), true);
    assert.equal(event.prevented, true);
    assert.equal(root.focusCalled, 1);
  } finally {
    Object.defineProperty(globalThis, 'window', { configurable: true, value: originalWindow });
    Object.defineProperty(globalThis, 'document', { configurable: true, value: originalDocument });
    Object.defineProperty(globalThis, 'HTMLElement', { configurable: true, value: originalHTMLElement });
  }
});

test('collectModalTabScopeRootsFromBodyChildren keeps the top modal and non-inert portal roots while excluding inert lower modals', () => {
  class FakeHTMLElement {
    constructor(
      readonly name: string,
      private readonly inert = false,
      private readonly ariaHidden: string | null = null,
    ) {}
    hasAttribute(name: string): boolean {
      return name === 'inert' ? this.inert : false;
    }
    getAttribute(name: string): string | null {
      return name === 'aria-hidden' ? this.ariaHidden : null;
    }
  }

  const topModal = new FakeHTMLElement('top-modal');
  const lowerModal = new FakeHTMLElement('lower-modal', true, 'true');
  const portalRoot = new FakeHTMLElement('portal-root');
  const originalHTMLElement = globalThis.HTMLElement;
  Object.defineProperty(globalThis, 'HTMLElement', {
    configurable: true,
    value: FakeHTMLElement,
  });

  try {
    const roots = collectModalTabScopeRootsFromBodyChildren(
      [topModal, lowerModal, portalRoot] as unknown as Element[],
      topModal as unknown as Element,
    );

    assert.deepEqual(
      roots.map((root) => (root as unknown as FakeHTMLElement).name),
      ['top-modal', 'portal-root'],
    );
  } finally {
    Object.defineProperty(globalThis, 'HTMLElement', { configurable: true, value: originalHTMLElement });
  }
});

test('recoverTopModalFocusWhenBodyActive only restores focus into the current top modal', () => {
  const focusCalls: string[] = [];
  const topPanel = {
    focus() {
      focusCalls.push('top');
    },
  };
  const originalDocument = globalThis.document;
  Object.defineProperty(globalThis, 'document', {
    configurable: true,
    value: {
      body: { nodeName: 'BODY' },
    },
  });

  try {
    assert.equal(
      recoverTopModalFocusWhenBodyActive(globalThis.document.body as unknown as Element, topPanel),
      true,
    );
    assert.equal(
      recoverTopModalFocusWhenBodyActive({ nodeName: 'DIV' } as unknown as Element, topPanel),
      false,
    );
  } finally {
    Object.defineProperty(globalThis, 'document', { configurable: true, value: originalDocument });
  }

  assert.deepEqual(focusCalls, ['top']);
});

test('ModalShell registers global Escape and Tab listeners in capture phase so nested overlays cannot bypass them', () => {
  const registrations: Array<{ type: string; handler: unknown; options: unknown }> = [];
  const target = {
    addEventListener(type: string, handler: unknown, options?: unknown) {
      registrations.push({ type, handler, options });
    },
  };

  registerGlobalModalEscapeListener(target as unknown as Pick<Document, 'addEventListener'>);
  registerGlobalModalTabListener(target as unknown as Pick<Document, 'addEventListener'>);

  assert.deepEqual(
    registrations.map(({ type, options }) => ({ type, options })),
    [
      { type: 'keydown', options: true },
      { type: 'keydown', options: true },
    ],
  );
  assert.notEqual(registrations[0]?.handler, registrations[1]?.handler);
});

test('ModalShell defers global Escape close so nested controls can cancel it via preventDefault', () => {
  const scheduled: Array<() => void> = [];
  const closeCalls: string[] = [];
  const escapeEvent = {
    defaultPrevented: false,
    isComposing: false,
    key: 'Escape',
  };

  assert.equal(
    scheduleGlobalModalEscapeClose(
      escapeEvent,
      () => {
        closeCalls.push('closed');
      },
      (cb) => {
        scheduled.push(cb);
      },
    ),
    true,
  );

  escapeEvent.defaultPrevented = true;
  scheduled.shift()?.();
  assert.deepEqual(closeCalls, []);

  escapeEvent.defaultPrevented = false;
  scheduleGlobalModalEscapeClose(
    escapeEvent,
    () => {
      closeCalls.push('closed');
    },
    (cb) => {
      scheduled.push(cb);
    },
  );
  scheduled.shift()?.();
  assert.deepEqual(closeCalls, ['closed']);
});

test('ModalShell dismisses backdrop clicks outside the panel while preserving clicks inside the panel', () => {
  const insideTarget = {};
  const outsideTarget = {};
  const panel = {
    contains(node: Node) {
      return node === insideTarget;
    },
  };

  assert.equal(
    shouldDismissModalFromBackdropClick(insideTarget as unknown as EventTarget, panel, true),
    false,
  );
  assert.equal(
    shouldDismissModalFromBackdropClick(outsideTarget as unknown as EventTarget, panel, true),
    true,
  );
  assert.equal(
    shouldDismissModalFromBackdropClick(outsideTarget as unknown as EventTarget, panel, false),
    false,
  );
});

test('parseString accepts canonical JSON strings and fails closed for non-strings', () => {
  const parse = parseString('fallback');

  assert.equal(parse('"hello"'), 'hello');
  assert.equal(parse('raw-string'), 'fallback');
  assert.equal(parse('null'), 'fallback');
  assert.equal(parse('42'), 'fallback');
  assert.equal(parse('true'), 'fallback');
  assert.equal(parse(null), 'fallback');
});

test('hexWithAlpha replaces or appends alpha without corrupting valid alpha-bearing hex colors', () => {
  assert.equal(hexWithAlpha('#abc', '20'), '#aabbcc20');
  assert.equal(hexWithAlpha('#abcd', '20'), '#aabbcc20');
  assert.equal(hexWithAlpha('#aabbcc', '20'), '#aabbcc20');
  assert.equal(hexWithAlpha('#aabbccdd', '20'), '#aabbcc20');
  assert.equal(hexWithAlpha('#zzzzzz', '20'), '#zzzzzz');
});
