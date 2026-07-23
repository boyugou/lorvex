import { describe, expect, it } from 'vitest';

import {
  installBackgroundMaintenanceLoop,
  type BackgroundMaintenanceTimerHandle,
  type BackgroundMaintenanceTimerHost,
} from './useBackgroundMaintenance.runtime';

// In-memory timer host that records every scheduled callback so tests
// can drive the loop deterministically. The real browser host is a
// thin wrapper over `setTimeout` / `clearTimeout`; the loop primitive
// is otherwise pure.
function createControlledTimerHost(): {
  host: BackgroundMaintenanceTimerHost;
  scheduled: { delay: number; callback: () => void }[];
  cleared: BackgroundMaintenanceTimerHandle[];
  flushNext: () => Promise<void>;
} {
  const scheduled: { delay: number; callback: () => void }[] = [];
  const cleared: BackgroundMaintenanceTimerHandle[] = [];
  let nextHandle = 0;
  const host: BackgroundMaintenanceTimerHost = {
    setTimeout: (callback, delay) => {
      scheduled.push({ delay, callback });
      const handle = ++nextHandle as unknown as BackgroundMaintenanceTimerHandle;
      return handle;
    },
    clearTimeout: (handle) => {
      cleared.push(handle);
    },
  };
  const flushNext = async () => {
    const next = scheduled.shift();
    if (!next) throw new Error('no scheduled tick to flush');
    next.callback();
    // Let the resulting microtask + finally chain drain before the
    // next assertion. Two awaits because `run().catch().finally()`
    // schedules the next setTimeout one extra microtask down.
    await Promise.resolve();
    await Promise.resolve();
  };
  return { host, scheduled, cleared, flushNext };
}

describe('installBackgroundMaintenanceLoop', () => {
  it('routes a thrown error from `run` to onError and reschedules the next tick (#3284)', async () => {
    const { host, scheduled, flushNext } = createControlledTimerHost();
    const errors: unknown[] = [];
    const ticks: number[] = [];
    let tickIndex = 0;
    const cleanup = installBackgroundMaintenanceLoop({
      delayMs: 1234,
      run: async () => {
        const id = ++tickIndex;
        ticks.push(id);
        if (id === 1) throw new Error('first-tick-boom');
      },
      onError: (error) => {
        errors.push(error);
      },
      timerHost: host,
    });

    // tick 1 fires synchronously when the loop is installed
    await Promise.resolve();
    await Promise.resolve();
    expect(ticks).toEqual([1]);
    expect(errors).toHaveLength(1);
    expect((errors[0] as Error).message).toBe('first-tick-boom');
    // a single follow-on tick was scheduled at the configured delay
    expect(scheduled).toHaveLength(1);
    expect(scheduled[0]?.delay).toBe(1234);

    // tick 2 fires successfully — onError must NOT fire again
    await flushNext();
    expect(ticks).toEqual([1, 2]);
    expect(errors).toHaveLength(1);
    // and the loop reschedules itself for tick 3
    expect(scheduled).toHaveLength(1);

    cleanup();
  });

  it('survives an exception from onError without breaking the reschedule cadence (#3284)', async () => {
    const { host, scheduled, flushNext } = createControlledTimerHost();
    let errorCallbackInvocations = 0;
    let tickIndex = 0;
    const cleanup = installBackgroundMaintenanceLoop({
      delayMs: 500,
      run: async () => {
        tickIndex += 1;
        if (tickIndex === 1) throw new Error('run-failure');
      },
      onError: () => {
        errorCallbackInvocations += 1;
        // A faulty logger must not break the maintenance loop —
        // the primitive swallows this re-throw on purpose.
        throw new Error('logger-failure');
      },
      timerHost: host,
    });

    await Promise.resolve();
    await Promise.resolve();
    expect(tickIndex).toBe(1);
    expect(errorCallbackInvocations).toBe(1);
    // the loop still scheduled the next tick despite the logger throw
    expect(scheduled).toHaveLength(1);

    await flushNext();
    expect(tickIndex).toBe(2);

    cleanup();
  });

  it('cleans up the pending timer when cancellation lands before the next tick fires', async () => {
    const { host, scheduled, cleared } = createControlledTimerHost();
    const cleanup = installBackgroundMaintenanceLoop({
      delayMs: 100,
      run: async () => {
        // empty — we only care about the post-tick scheduling
      },
      onError: () => undefined,
      timerHost: host,
    });

    // let tick 1 finish + queue tick 2
    await Promise.resolve();
    await Promise.resolve();
    expect(scheduled).toHaveLength(1);

    cleanup();
    expect(cleared).toHaveLength(1);
  });
});
