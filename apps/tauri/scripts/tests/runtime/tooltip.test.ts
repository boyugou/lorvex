import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

// The runtime-logic test suite runs without a React renderer or jsdom,
// so we can't mount the full Tooltip component. Instead we verify:
//
//   1. The pure positioning function (`computeTooltipPosition`) which
//      the component uses to place its portal — imported directly.
//
//   2. The show/hide/immediate state machine that drives visibility.
//      We rebuild a structurally-identical twin of `useTooltipState`
//      here that swaps React's useState/useRef/useEffect for an
//      in-memory store and uses a fake scheduler instead of real
//      timers. Any change to the production state machine in
//      app/src/components/ui/Tooltip.tsx MUST be mirrored in the
//      `buildTooltipStateMachine` helper below, and the tests below
//      exercise every transition (closed → opening → open → closing
//      → closed, plus the cancel/hideImmediately paths).

import {
  TOOLTIP_DEFAULT_DELAY_MS,
} from '../../../app/src/components/ui/Tooltip';
import {
  clearTooltipTimer,
  computeTooltipPosition,
  createBrowserTooltipTimerHost,
  installTooltipDismissRuntime,
  mergeTooltipTriggerDescribedBy,
  scheduleTooltipTimer,
  shouldDismissTooltipFromKeyEvent,
  type TooltipTimerHost,
} from '../../../app/src/components/ui/Tooltip.runtime';

// -----------------------------------------------------------------------------
// Fake scheduler
// -----------------------------------------------------------------------------

interface FakeScheduler {
  readonly now: () => number;
  add(fn: () => void, ms: number): number;
  cancel(handle: number): void;
  advance(ms: number): void;
  reset(): void;
}

function createScheduler(): FakeScheduler {
  let nextId = 1;
  const pending = new Map<number, { at: number; fn: () => void }>();
  let now = 0;
  return {
    now: () => now,
    add(fn, ms) {
      const id = nextId++;
      pending.set(id, { at: now + ms, fn });
      return id;
    },
    cancel(handle) {
      pending.delete(handle);
    },
    advance(ms) {
      now += ms;
      for (const [id, entry] of [...pending.entries()]) {
        if (entry.at <= now) {
          pending.delete(id);
          entry.fn();
        }
      }
    },
    reset() {
      pending.clear();
      nextId = 1;
      now = 0;
    },
  };
}

// -----------------------------------------------------------------------------
// State-machine twin (mirrors useTooltipState semantics).
// -----------------------------------------------------------------------------

type Visibility = 'closed' | 'opening' | 'open' | 'closing';

interface TooltipMachine {
  readonly visibility: () => Visibility;
  readonly isMounted: () => boolean;
  show(): void;
  hide(): void;
  hideImmediately(): void;
}

interface MachineOptions {
  delayMs?: number;
  hideDelayMs?: number;
  scheduler: FakeScheduler;
}

function buildTooltipStateMachine(opts: MachineOptions): TooltipMachine {
  const { scheduler } = opts;
  const delayMs = opts.delayMs ?? TOOLTIP_DEFAULT_DELAY_MS;
  const hideDelayMs = opts.hideDelayMs ?? 80;
  let visibility: Visibility = 'closed';
  let timer: number | null = null;

  function cancelTimer() {
    if (timer != null) {
      scheduler.cancel(timer);
      timer = null;
    }
  }

  return {
    visibility: () => visibility,
    isMounted: () => visibility !== 'closed',
    show() {
      cancelTimer();
      visibility = visibility === 'open' ? 'open' : 'opening';
      timer = scheduler.add(() => {
        timer = null;
        visibility = 'open';
      }, delayMs);
    },
    hide() {
      cancelTimer();
      if (visibility === 'closed') return;
      if (visibility === 'opening') {
        visibility = 'closed';
        return;
      }
      visibility = 'closing';
      timer = scheduler.add(() => {
        timer = null;
        visibility = 'closed';
      }, hideDelayMs);
    },
    hideImmediately() {
      cancelTimer();
      visibility = 'closed';
    },
  };
}

// -----------------------------------------------------------------------------
// State-machine tests
// -----------------------------------------------------------------------------

test('tooltip state: starts closed and unmounted', () => {
  const scheduler = createScheduler();
  const m = buildTooltipStateMachine({ scheduler });
  assert.equal(m.visibility(), 'closed');
  assert.equal(m.isMounted(), false);
});

test('tooltip state: show() opens after delay (default 400 ms)', () => {
  const scheduler = createScheduler();
  const m = buildTooltipStateMachine({ scheduler, delayMs: 400 });
  m.show();
  assert.equal(m.visibility(), 'opening', 'mounts in opening state so DOM is ready for animation');
  assert.equal(m.isMounted(), true);
  scheduler.advance(399);
  assert.equal(m.visibility(), 'opening');
  scheduler.advance(1);
  assert.equal(m.visibility(), 'open');
});

test('tooltip state: hide() during the open delay cancels and returns to closed', () => {
  const scheduler = createScheduler();
  const m = buildTooltipStateMachine({ scheduler, delayMs: 400 });
  m.show();
  m.hide();
  assert.equal(m.visibility(), 'closed');
  scheduler.advance(1000);
  assert.equal(m.visibility(), 'closed', 'the pending show timer must have been cancelled');
});

test('tooltip state: hide() from open transitions through closing → closed', () => {
  const scheduler = createScheduler();
  const m = buildTooltipStateMachine({ scheduler, delayMs: 50, hideDelayMs: 80 });
  m.show();
  scheduler.advance(50);
  assert.equal(m.visibility(), 'open');
  m.hide();
  assert.equal(m.visibility(), 'closing', 'intermediate state plays the fade-out');
  scheduler.advance(79);
  assert.equal(m.visibility(), 'closing');
  scheduler.advance(1);
  assert.equal(m.visibility(), 'closed');
});

test('tooltip state: hideImmediately() skips the closing fade', () => {
  const scheduler = createScheduler();
  const m = buildTooltipStateMachine({ scheduler, delayMs: 50 });
  m.show();
  scheduler.advance(50);
  m.hideImmediately();
  assert.equal(m.visibility(), 'closed');
});

test('tooltip state: show() while open is a no-op', () => {
  const scheduler = createScheduler();
  const m = buildTooltipStateMachine({ scheduler, delayMs: 50 });
  m.show();
  scheduler.advance(50);
  assert.equal(m.visibility(), 'open');
  m.show();
  assert.equal(m.visibility(), 'open', 'second show() must not retrigger the opening animation');
});

test('tooltip state: rapid show→hide→show reopens cleanly', () => {
  const scheduler = createScheduler();
  const m = buildTooltipStateMachine({ scheduler, delayMs: 100 });
  m.show();
  m.hide();
  m.show();
  assert.equal(m.visibility(), 'opening');
  scheduler.advance(100);
  assert.equal(m.visibility(), 'open');
});

// -----------------------------------------------------------------------------
// Positioning — pure function, tested directly.
// -----------------------------------------------------------------------------

test('computeTooltipPosition: centers above trigger on side=top', () => {
  const pos = computeTooltipPosition(
    { top: 100, left: 100, width: 40, height: 20 },
    { width: 80, height: 24 },
    { width: 1000, height: 800 },
    'top',
    6,
  );
  assert.equal(pos.x, 100 + 20 - 40); // trigger center 120 - half tooltip width 40 = 80
  assert.equal(pos.y, 100 - 24 - 6);
});

test('computeTooltipPosition: centers below trigger on side=bottom', () => {
  const pos = computeTooltipPosition(
    { top: 100, left: 100, width: 40, height: 20 },
    { width: 80, height: 24 },
    { width: 1000, height: 800 },
    'bottom',
    6,
  );
  assert.equal(pos.x, 80);
  assert.equal(pos.y, 126);
});

test('computeTooltipPosition: clamps to 8px viewport margin when flush left', () => {
  const pos = computeTooltipPosition(
    { top: 50, left: 0, width: 10, height: 10 },
    { width: 200, height: 24 },
    { width: 400, height: 300 },
    'top',
    6,
  );
  assert.equal(pos.x, 8, 'no negative x — clamps into the viewport');
});

test('computeTooltipPosition: clamps when trigger is flush right', () => {
  const pos = computeTooltipPosition(
    { top: 50, left: 390, width: 10, height: 10 },
    { width: 200, height: 24 },
    { width: 400, height: 300 },
    'top',
    6,
  );
  // maxX = viewport 400 − tooltip 200 − margin 8 = 192
  assert.equal(pos.x, 192);
});

test('computeTooltipPosition: side=left places tooltip to the left and vertically centers', () => {
  const pos = computeTooltipPosition(
    { top: 100, left: 200, width: 40, height: 20 },
    { width: 60, height: 24 },
    { width: 1000, height: 800 },
    'left',
    6,
  );
  assert.equal(pos.x, 200 - 60 - 6); // 134
  assert.equal(pos.y, 100 + 10 - 12); // center y = 98
});

test('tooltip dismiss key predicate accepts only non-composing Escape', () => {
  assert.equal(shouldDismissTooltipFromKeyEvent({ key: 'Escape' }), true);
  assert.equal(shouldDismissTooltipFromKeyEvent({ key: 'Enter' }), false);
  assert.equal(shouldDismissTooltipFromKeyEvent({ key: 'Escape', isComposing: true }), false);
});

test('tooltip dismiss runtime hides on scroll, resize, and Escape, then unregisters listeners', () => {
  const calls: string[] = [];
  let scrollListener: (() => void) | undefined;
  let resizeListener: (() => void) | undefined;
  let keydownListener: ((event: KeyboardEvent) => void) | undefined;

  const cleanup = installTooltipDismissRuntime({
    addWindowScrollListener: (listener) => {
      scrollListener = listener;
      return () => {
        scrollListener = undefined;
        calls.push('cleanup-scroll');
      };
    },
    addWindowResizeListener: (listener) => {
      resizeListener = listener;
      return () => {
        resizeListener = undefined;
        calls.push('cleanup-resize');
      };
    },
    addWindowKeydownListener: (listener) => {
      keydownListener = listener;
      return () => {
        keydownListener = undefined;
        calls.push('cleanup-keydown');
      };
    },
    onDismiss: () => calls.push('dismiss'),
  });

  scrollListener?.();
  resizeListener?.();
  keydownListener?.({ key: 'Enter' } as KeyboardEvent);
  keydownListener?.({ key: 'Escape', isComposing: true } as KeyboardEvent);
  keydownListener?.({ key: 'Escape' } as KeyboardEvent);
  cleanup();

  assert.deepEqual(calls, [
    'dismiss',
    'dismiss',
    'dismiss',
    'cleanup-scroll',
    'cleanup-resize',
    'cleanup-keydown',
  ]);
  assert.equal(scrollListener, undefined);
  assert.equal(resizeListener, undefined);
  assert.equal(keydownListener, undefined);
});

test('tooltip dismiss runtime is inert without window hosts', () => {
  const cleanup = installTooltipDismissRuntime({
    addWindowScrollListener: null,
    addWindowResizeListener: null,
    addWindowKeydownListener: null,
    onDismiss: () => {
      throw new Error('dismiss should not run without installed listeners');
    },
  });

  cleanup();
});

test('tooltip timer runtime schedules and clears through the injected host', () => {
  const callbacks: Array<() => void> = [];
  const clearedHandles: unknown[] = [];
  const delays: number[] = [];
  const host: TooltipTimerHost = {
    clearTimeout: (handle) => {
      clearedHandles.push(handle);
    },
    setTimeout: (callback, delayMs) => {
      callbacks.push(callback);
      delays.push(delayMs);
      return `tooltip-timer-${callbacks.length}`;
    },
  };

  let callbackCount = 0;
  const handle = scheduleTooltipTimer(host, () => {
    callbackCount += 1;
  }, 400);

  assert.equal(handle, 'tooltip-timer-1');
  assert.deepEqual(delays, [400]);
  assert.equal(callbackCount, 0);

  callbacks[0]?.();
  assert.equal(callbackCount, 1);

  clearTooltipTimer(host, handle);
  clearTooltipTimer(host, null);
  assert.deepEqual(clearedHandles, ['tooltip-timer-1']);
});

test('tooltip aria description merge preserves existing trigger descriptions', () => {
  assert.equal(
    mergeTooltipTriggerDescribedBy('existing-id', 'tooltip-id'),
    'existing-id tooltip-id',
  );
  assert.equal(
    mergeTooltipTriggerDescribedBy('existing-id tooltip-id', 'tooltip-id'),
    'existing-id tooltip-id',
  );
  assert.equal(mergeTooltipTriggerDescribedBy(undefined, 'tooltip-id'), 'tooltip-id');
  assert.equal(mergeTooltipTriggerDescribedBy('existing-id', undefined), 'existing-id');
  assert.equal(mergeTooltipTriggerDescribedBy('', undefined), undefined);
});

test('tooltip component delegates positioning, timers, and window dismissal wiring to runtime helpers', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/ui/Tooltip.tsx'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/ui/Tooltip.runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*clearTooltipTimer,[\s\S]*computeTooltipPosition,[\s\S]*createBrowserTooltipTimerHost,[\s\S]*installTooltipDismissRuntime,[\s\S]*scheduleTooltipTimer,[\s\S]*type TooltipSide,[\s\S]*\} from '\.\/Tooltip\.runtime';/s,
  );
  assert.match(source, /const tooltipTimerHost = createBrowserTooltipTimerHost\(\);/);
  assert.match(source, /return scheduleTooltipTimer\(tooltipTimerHost, fn, ms\);/);
  assert.match(source, /clearTooltipTimer\(tooltipTimerHost, handle\);/);
  assert.match(source, /const next = computeTooltipPosition\(/);
  assert.match(
    source,
    /return installTooltipDismissRuntime\(\{[\s\S]*addWindowScrollListener: typeof window === 'undefined'[\s\S]*window\.addEventListener\('scroll', listener, \{ capture: true, passive: true \}\);[\s\S]*addWindowResizeListener: typeof window === 'undefined'[\s\S]*window\.addEventListener\('resize', listener\);[\s\S]*addWindowKeydownListener: typeof window === 'undefined'[\s\S]*window\.addEventListener\('keydown', listener\);[\s\S]*onDismiss: hideImmediately,/s,
  );
  assert.doesNotMatch(source, /(?<!\.)\bsetTimeout\(/);
  assert.doesNotMatch(source, /(?<!\.)\bclearTimeout\(/);
  assert.doesNotMatch(source, /const handleScroll = \(\) => hideImmediately\(\);/);
  assert.doesNotMatch(source, /const handleKey = \(event: KeyboardEvent\) => \{/);

  assert.match(runtimeSource, /export function createBrowserTooltipTimerHost\(\): TooltipTimerHost/);
  assert.match(runtimeSource, /globalThis\.clearTimeout\(handle as ReturnType<typeof globalThis\.setTimeout>\);/);
  assert.match(runtimeSource, /setTimeout: \(callback, delayMs\) => globalThis\.setTimeout\(callback, delayMs\),/);
});

test('tooltip runtime owns the browser timer host wiring', () => {
  const host = createBrowserTooltipTimerHost();
  assert.equal(typeof host.setTimeout, 'function');
  assert.equal(typeof host.clearTimeout, 'function');
});

test('tooltip component attaches aria description to the focused trigger child', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/ui/Tooltip.tsx'),
    'utf8',
  );
  const wrapperOpenTag = source.match(/<span[\s\S]*?>/)?.[0] ?? '';

  assert.match(source, /isValidElement\(children\)/);
  assert.match(source, /cloneElement\(/);
  assert.match(source, /mergeTooltipTriggerDescribedBy\(/);
  assert.doesNotMatch(
    wrapperOpenTag,
    /aria-describedby=/,
    'the display:contents wrapper is presentational; the focused child receives aria-describedby',
  );
});
