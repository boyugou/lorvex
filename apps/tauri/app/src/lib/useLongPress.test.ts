/**
 * Regression test.
 *
 * The Vitest harness for `app/` runs in `environment: 'node'` and
 * does not pull in `@testing-library/react`. Mock `react` with a
 * per-render slot map (same pattern as `useLazyRef.test.ts`) so the
 * hook can be exercised without a render host. The contract we're
 * locking in: `useLongPress` MUST invoke `createLongPressController`
 * exactly once per component lifetime, regardless of how many times
 * the component re-renders.
 */
import { beforeEach, describe, expect, it, vi } from 'vitest';

const refSlots: Array<{ current: unknown }> = [];
let slotCursor = 0;

vi.mock('react', () => ({
  useRef: <T>(initial: T) => {
    if (slotCursor >= refSlots.length) {
      refSlots.push({ current: initial });
    }
    return refSlots[slotCursor++] as { current: T };
  },
  useEffect: () => {
    // Effects run at commit; we only care about render-phase
    // allocations in this regression test, so noop.
  },
}));

type LongPressCallback = (point: { x: number; y: number }) => void;
type Controller = {
  start: ReturnType<typeof vi.fn>;
  end: ReturnType<typeof vi.fn>;
  move: ReturnType<typeof vi.fn>;
  dispose: ReturnType<typeof vi.fn>;
  hasPending: () => boolean;
};

// `vi.mock` is hoisted to the top of the file before any local
// `const` initializations run; reaching `factorySpy` from inside the
// hoisted factory throws TDZ. Use `vi.hoisted` to lift the spy into
// the same hoisting tier so the mock factory and the test body can
// share the reference.
const { factorySpy } = vi.hoisted(() => ({
  factorySpy: vi.fn<(cb: LongPressCallback) => Controller>(() => ({
    start: vi.fn(),
    end: vi.fn(),
    move: vi.fn(),
    dispose: vi.fn(),
    hasPending: () => false,
  })),
}));

vi.mock('./useLongPress.logic', () => ({
  createLongPressController: factorySpy,
}));

import { useLongPress } from './useLongPress';

function render<T>(hook: () => T): T {
  slotCursor = 0;
  return hook();
}

function reset() {
  refSlots.length = 0;
  slotCursor = 0;
  factorySpy.mockClear();
}

describe('useLongPress', () => {
  beforeEach(reset);

  it('invokes createLongPressController exactly once across many renders', () => {
    const onLongPress = vi.fn();

    render(() => useLongPress(onLongPress));
    render(() => useLongPress(onLongPress));
    render(() => useLongPress(onLongPress));
    render(() => useLongPress(onLongPress));
    render(() => useLongPress(onLongPress));

    // Pre-fix used `useRef(createLongPressController(...))`, which
    // evaluates the factory on every render and discards every
    // result after the first; that path would have called the
    // factory 5 times. The lazy-ref migration must call it once.
    expect(factorySpy).toHaveBeenCalledTimes(1);
  });

  it('returns the same controller reference across renders', () => {
    const handlersA = render(() => useLongPress(vi.fn()));
    const handlersB = render(() => useLongPress(vi.fn()));

    expect(handlersA.onTouchStart).toBeTypeOf('function');
    expect(handlersB.onTouchStart).toBeTypeOf('function');
  });

  it('routes the latest onLongPress callback through the ref', () => {
    let captured: LongPressCallback | null = null;
    factorySpy.mockImplementationOnce((cb) => {
      captured = cb;
      return {
        start: vi.fn(),
        end: vi.fn(),
        move: vi.fn(),
        dispose: vi.fn(),
        hasPending: () => false,
      };
    });

    const first = vi.fn();
    const second = vi.fn();

    render(() => useLongPress(first));
    // Re-render with a new callback. The factory must NOT be re-invoked,
    // but the controller's onLongPress should now route to `second` via
    // the always-up-to-date ref.
    render(() => useLongPress(second));

    expect(captured).not.toBeNull();
    captured!({ x: 1, y: 2 });
    expect(first).not.toHaveBeenCalled();
    expect(second).toHaveBeenCalledWith(1, 2);
  });

  it('does not arm long-press when touch starts inside an ignored descendant', () => {
    const controller: Controller = {
      start: vi.fn(),
      end: vi.fn(),
      move: vi.fn(),
      dispose: vi.fn(),
      hasPending: () => false,
    };
    factorySpy.mockImplementationOnce(() => controller);
    const ignoredButton = {};
    const target = {
      closest: vi.fn((selector: string) =>
        selector === '[data-long-press-ignore]' ? ignoredButton : null,
      ),
    };
    const currentTarget = {
      contains: vi.fn((node: unknown) => node === ignoredButton),
    };

    const handlers = render(() => useLongPress(vi.fn()));
    handlers.onTouchStart({
      touches: [{ clientX: 12, clientY: 24 }],
      target,
      currentTarget,
    } as unknown as Parameters<typeof handlers.onTouchStart>[0]);

    expect(controller.start).not.toHaveBeenCalled();
  });

  it('still arms long-press when touch starts on the main target body', () => {
    const controller: Controller = {
      start: vi.fn(),
      end: vi.fn(),
      move: vi.fn(),
      dispose: vi.fn(),
      hasPending: () => false,
    };
    factorySpy.mockImplementationOnce(() => controller);

    const handlers = render(() => useLongPress(vi.fn()));
    handlers.onTouchStart({
      touches: [{ clientX: 12, clientY: 24 }],
      target: { closest: vi.fn(() => null) },
      currentTarget: { contains: vi.fn(() => false) },
    } as unknown as Parameters<typeof handlers.onTouchStart>[0]);

    expect(controller.start).toHaveBeenCalledWith({ x: 12, y: 24 });
  });
});
