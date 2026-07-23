import { describe, expect, it, vi } from 'vitest';

import {
  computeSyncCadenceDelay,
  QUICK_RETRY_MS,
  shouldForceAndroidResumeResync,
  SYNC_LOOP_ANDROID_BACKGROUND_MS,
  SYNC_LOOP_DESKTOP_HIDDEN_MS,
  SYNC_LOOP_DESKTOP_LOW_BANDWIDTH_MS,
  SYNC_LOOP_ERROR_BACKOFF_MAX_MS,
  SYNC_LOOP_OFFLINE_MS,
} from './cadence';

describe('computeSyncCadenceDelay', () => {
  it('prioritizes quick retry before offline and error backoff states', () => {
    expect(computeSyncCadenceDelay({
      mobilePlatform: 'unknown',
      online: false,
      visible: false,
      lowBandwidth: true,
      saveData: true,
      consecutiveErrorCount: 8,
      quickRetryRequested: true,
    })).toBe(QUICK_RETRY_MS);
  });

  it('uses the offline cadence when no quick retry is pending', () => {
    expect(computeSyncCadenceDelay({
      mobilePlatform: 'android',
      online: false,
      visible: true,
      lowBandwidth: false,
      saveData: false,
      consecutiveErrorCount: 0,
      quickRetryRequested: false,
    })).toBe(SYNC_LOOP_OFFLINE_MS);
  });

  it('stretches desktop cadence for hidden and constrained-network states', () => {
    expect(computeSyncCadenceDelay({
      mobilePlatform: 'unknown',
      online: true,
      visible: true,
      lowBandwidth: false,
      saveData: false,
      consecutiveErrorCount: 0,
      quickRetryRequested: false,
    })).toBe(60_000);

    expect(computeSyncCadenceDelay({
      mobilePlatform: 'unknown',
      online: true,
      visible: false,
      lowBandwidth: false,
      saveData: false,
      consecutiveErrorCount: 0,
      quickRetryRequested: false,
    })).toBe(SYNC_LOOP_DESKTOP_HIDDEN_MS);

    expect(computeSyncCadenceDelay({
      mobilePlatform: 'unknown',
      online: true,
      visible: true,
      lowBandwidth: false,
      saveData: true,
      consecutiveErrorCount: 0,
      quickRetryRequested: false,
    })).toBe(SYNC_LOOP_DESKTOP_LOW_BANDWIDTH_MS);
  });

  it('uses mobile platform cadence floors for active, hidden, and constrained-network states', () => {
    expect(computeSyncCadenceDelay({
      mobilePlatform: 'android',
      online: true,
      visible: true,
      lowBandwidth: false,
      saveData: false,
      consecutiveErrorCount: 0,
      quickRetryRequested: false,
    })).toBe(120_000);

    expect(computeSyncCadenceDelay({
      mobilePlatform: 'android',
      online: true,
      visible: false,
      lowBandwidth: false,
      saveData: false,
      consecutiveErrorCount: 0,
      quickRetryRequested: false,
    })).toBe(SYNC_LOOP_ANDROID_BACKGROUND_MS);

    expect(computeSyncCadenceDelay({
      mobilePlatform: 'android',
      online: true,
      visible: true,
      lowBandwidth: true,
      saveData: false,
      consecutiveErrorCount: 0,
      quickRetryRequested: false,
    })).toBe(240_000);
  });

  it('applies deterministic jittered error backoff without undercutting the platform floor', () => {
    const randomSpy = vi.spyOn(Math, 'random').mockReturnValue(0.5);
    try {
      expect(computeSyncCadenceDelay({
        mobilePlatform: 'unknown',
        online: true,
        visible: true,
        lowBandwidth: false,
        saveData: false,
        consecutiveErrorCount: 1,
        quickRetryRequested: false,
      })).toBe(60_000);

      expect(computeSyncCadenceDelay({
        mobilePlatform: 'unknown',
        online: true,
        visible: true,
        lowBandwidth: false,
        saveData: false,
        consecutiveErrorCount: 3,
        quickRetryRequested: false,
      })).toBe(120_000);

      expect(computeSyncCadenceDelay({
        mobilePlatform: 'unknown',
        online: true,
        visible: true,
        lowBandwidth: false,
        saveData: false,
        consecutiveErrorCount: 8,
        quickRetryRequested: false,
      })).toBe(SYNC_LOOP_ERROR_BACKOFF_MAX_MS);
    } finally {
      randomSpy.mockRestore();
    }
  });
});

describe('shouldForceAndroidResumeResync', () => {
  it('forces a visible android resume resync after the background cadence gap', () => {
    expect(shouldForceAndroidResumeResync(
      'android',
      1_000,
      1_000 + SYNC_LOOP_ANDROID_BACKGROUND_MS,
      true,
    )).toBe(true);
  });

  it('skips resume resync for non-android, hidden, missing, or too-recent ticks', () => {
    expect(shouldForceAndroidResumeResync(
      'android',
      1_000,
      1_000 + SYNC_LOOP_ANDROID_BACKGROUND_MS,
      false,
    )).toBe(false);
    expect(shouldForceAndroidResumeResync(
      'android',
      0,
      1_000 + SYNC_LOOP_ANDROID_BACKGROUND_MS,
      true,
    )).toBe(false);
    expect(shouldForceAndroidResumeResync(
      'android',
      1_000,
      999 + SYNC_LOOP_ANDROID_BACKGROUND_MS,
      true,
    )).toBe(false);
  });
});
