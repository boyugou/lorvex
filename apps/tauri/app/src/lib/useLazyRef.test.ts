import { beforeEach, describe, expect, it, vi } from 'vitest';

// The vitest harness for `app/` runs in `environment: 'node'` (see
// `app/vitest.config.ts`) and the workspace does not pull in
// `@testing-library/react` or `react-test-renderer`. To exercise
// `useLazyRef` without a render host we simulate React's hook contract
// by mocking `useRef` with a per-render slot map. This mirrors what
// React itself does — give the hook a stable storage slot keyed by
// call-site index and reset slots on each "render". The mock is only
// expressive enough for this test: `useLazyRef` is the only consumer.
const refSlots: Array<{ current: unknown }> = [];
let slotCursor = 0;

vi.mock('react', () => ({
  useRef: <T>(initial: T) => {
    if (slotCursor >= refSlots.length) {
      refSlots.push({ current: initial });
    }
    return refSlots[slotCursor++] as { current: T };
  },
}));

import { useLazyRef } from './useLazyRef';

function render<T>(hook: () => T): T {
  slotCursor = 0;
  return hook();
}

function reset() {
  refSlots.length = 0;
  slotCursor = 0;
}

describe('useLazyRef', () => {
  beforeEach(reset);

  it('calls the factory exactly once across multiple renders', () => {
    const factory = vi.fn(() => ({ counter: 0 }));

    const initial = render(() => useLazyRef(factory));
    const second = render(() => useLazyRef(factory));
    const third = render(() => useLazyRef(factory));

    expect(factory).toHaveBeenCalledTimes(1);
    expect(initial).toBe(second);
    expect(second).toBe(third);
  });

  it('preserves a `null` factory return without re-invoking the factory', () => {
    const factory = vi.fn(() => null);

    const ref = render(() => useLazyRef<null>(factory));
    expect(ref.current).toBeNull();

    render(() => useLazyRef<null>(factory));
    render(() => useLazyRef<null>(factory));

    expect(factory).toHaveBeenCalledTimes(1);
    expect(ref.current).toBeNull();
  });

  it('preserves an `undefined` factory return without re-invoking the factory', () => {
    const factory = vi.fn<() => undefined>(() => undefined);

    const ref = render(() => useLazyRef<undefined>(factory));
    expect(ref.current).toBeUndefined();

    render(() => useLazyRef<undefined>(factory));
    render(() => useLazyRef<undefined>(factory));

    expect(factory).toHaveBeenCalledTimes(1);
    expect(ref.current).toBeUndefined();
  });

  it('returns a mutable ref whose .current can be reassigned', () => {
    const ref = render(() => useLazyRef(() => ({ value: 'a' })));

    expect(ref.current.value).toBe('a');
    ref.current = { value: 'b' };
    expect(ref.current.value).toBe('b');

    const next = render(() => useLazyRef(() => ({ value: 'a' })));
    expect(next).toBe(ref);
    expect(next.current.value).toBe('b');
  });
});
