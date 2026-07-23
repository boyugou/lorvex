import type { MobilePlatform } from '../platform/platform';

import {
  RESUME_RESYNC_THROTTLE_MS,
  shouldForceAndroidResumeResync,
} from './cadence';

export const BACKGROUND_SYNC_INITIAL_DELAY_MS = 2_000;
export const BACKGROUND_SYNC_GENTLE_RESUME_DELAY_MS = 5_000;
const REPEATED_SYNC_FAILURE_TOAST_THRESHOLD = 3;

interface BackgroundSyncRuntimeHost {
  now(): number;
  isVisible(): boolean;
  schedule(delayMs: number): void;
}

interface BackgroundSyncRuntimeController {
  scheduleInitialTick(): void;
  handleCadenceResumeRequested(running: boolean): void;
  handleWindowFocus(running: boolean): void;
  handleVisibilityChange(running: boolean): void;
  handlePageShow(running: boolean): void;
  handleResume(running: boolean): void;
  getConsecutiveErrorCount(): number;
  consumeNextDelay(defaultDelayMs: number): number;
  consumeOverrideDelay(defaultDelayMs: number, overrideDelayMs: number): number;
  recordTickCompleted(): void;
  resetConsecutiveErrors(): void;
  recordTickError(): boolean;
}

interface CreateBackgroundSyncRuntimeControllerOptions {
  host: BackgroundSyncRuntimeHost;
  mobilePlatform: MobilePlatform;
}

export function createBackgroundSyncRuntimeController(
  options: CreateBackgroundSyncRuntimeControllerOptions,
): BackgroundSyncRuntimeController {
  const { host, mobilePlatform } = options;

  let forceImmediateTick = false;
  let lastResumeTriggerAt: number | null = null;
  let lastTickCompletedAt = 0;
  let consecutiveErrorCount = 0;

  const shouldForceResumeResync = (): boolean =>
    shouldForceAndroidResumeResync(
      mobilePlatform,
      lastTickCompletedAt,
      host.now(),
      host.isVisible(),
    );

  const requestImmediateTick = (running: boolean, bypassThrottle = false): void => {
    const now = host.now();
    if (
      !bypassThrottle &&
      lastResumeTriggerAt != null &&
      now - lastResumeTriggerAt < RESUME_RESYNC_THROTTLE_MS
    ) {
      return;
    }
    lastResumeTriggerAt = now;
    forceImmediateTick = true;
    if (!running) {
      host.schedule(0);
    }
  };

  return {
    scheduleInitialTick(): void {
      host.schedule(BACKGROUND_SYNC_INITIAL_DELAY_MS);
    },

    handleCadenceResumeRequested(running: boolean): void {
      requestImmediateTick(running, true);
    },

    handleWindowFocus(running: boolean): void {
      if (!running) {
        host.schedule(BACKGROUND_SYNC_GENTLE_RESUME_DELAY_MS);
      }
    },

    handleVisibilityChange(running: boolean): void {
      if (!host.isVisible()) return;
      if (shouldForceResumeResync()) {
        requestImmediateTick(running, true);
        return;
      }
      if (!running) {
        host.schedule(BACKGROUND_SYNC_GENTLE_RESUME_DELAY_MS);
      }
    },

    handlePageShow(running: boolean): void {
      if (shouldForceResumeResync()) {
        requestImmediateTick(running, true);
        return;
      }
      requestImmediateTick(running);
    },

    handleResume(running: boolean): void {
      if (shouldForceResumeResync()) {
        requestImmediateTick(running, true);
        return;
      }
      requestImmediateTick(running);
    },

    getConsecutiveErrorCount(): number {
      return consecutiveErrorCount;
    },

    consumeNextDelay(defaultDelayMs: number): number {
      const delay = forceImmediateTick ? 0 : defaultDelayMs;
      forceImmediateTick = false;
      return delay;
    },

    consumeOverrideDelay(defaultDelayMs: number, overrideDelayMs: number): number {
      forceImmediateTick = false;
      return Math.max(defaultDelayMs, overrideDelayMs);
    },

    recordTickCompleted(): void {
      lastTickCompletedAt = host.now();
    },

    resetConsecutiveErrors(): void {
      consecutiveErrorCount = 0;
    },

    recordTickError(): boolean {
      consecutiveErrorCount += 1;
      return consecutiveErrorCount === REPEATED_SYNC_FAILURE_TOAST_THRESHOLD;
    },
  };
}
