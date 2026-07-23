import { describe, expect, it, vi } from 'vitest';

import {
  createCalendarSubscriptionSyncController,
  SUBSCRIPTION_SYNC_MIN_GAP_MS,
} from './calendarSubscriptionSync.logic';

describe('createCalendarSubscriptionSyncController', () => {
  it('skips sync attempts while offline', async () => {
    const performSync = vi.fn<() => Promise<unknown>>().mockResolvedValue(undefined);
    const controller = createCalendarSubscriptionSyncController({
      isOnline: () => false,
      now: () => 1_000,
      performSync,
      reportError: vi.fn(),
    });

    await expect(controller.trySync()).resolves.toBe(false);
    await expect(controller.handleConnectionChange()).resolves.toBe(false);

    expect(performSync).not.toHaveBeenCalled();
    expect(controller.getLastAttemptAt()).toBeNull();
    expect(controller.isSyncing()).toBe(false);
  });

  it('records an attempt and throttles repeated online attempts inside the minimum gap', async () => {
    let now = 10_000;
    const performSync = vi.fn<() => Promise<unknown>>().mockResolvedValue(undefined);
    const controller = createCalendarSubscriptionSyncController({
      isOnline: () => true,
      now: () => now,
      performSync,
      reportError: vi.fn(),
    });

    await expect(controller.trySync()).resolves.toBe(true);
    expect(controller.getLastAttemptAt()).toBe(10_000);

    now += SUBSCRIPTION_SYNC_MIN_GAP_MS - 1;
    await expect(controller.handleOnline()).resolves.toBe(false);

    now += 1;
    await expect(controller.handleConnectionChange()).resolves.toBe(true);

    expect(performSync).toHaveBeenCalledTimes(2);
    expect(controller.getLastAttemptAt()).toBe(10_000 + SUBSCRIPTION_SYNC_MIN_GAP_MS);
  });

  it('prevents concurrent sync attempts while preserving the in-flight state', async () => {
    let resolveSync: ((value: unknown) => void) | undefined;
    const performSync = vi.fn<() => Promise<unknown>>().mockImplementation(
      () => new Promise((resolve) => {
        resolveSync = resolve;
      }),
    );
    const controller = createCalendarSubscriptionSyncController({
      isOnline: () => true,
      now: () => 42_000,
      performSync,
      reportError: vi.fn(),
    });

    const firstAttempt = controller.trySync();
    expect(controller.isSyncing()).toBe(true);
    await expect(controller.trySync()).resolves.toBe(false);
    expect(performSync).toHaveBeenCalledTimes(1);

    resolveSync?.(undefined);
    await expect(firstAttempt).resolves.toBe(true);
    expect(controller.isSyncing()).toBe(false);
  });

  it('reports sync errors and releases the in-flight guard', async () => {
    const error = new Error('subscription fetch failed');
    const reportError = vi.fn();
    const controller = createCalendarSubscriptionSyncController({
      isOnline: () => true,
      now: () => 25_000,
      performSync: vi.fn<() => Promise<unknown>>().mockRejectedValue(error),
      reportError,
    });

    await expect(controller.trySync()).resolves.toBe(true);

    expect(reportError).toHaveBeenCalledWith(error);
    expect(controller.isSyncing()).toBe(false);
    expect(controller.getLastAttemptAt()).toBe(25_000);
  });
});
