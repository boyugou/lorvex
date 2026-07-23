import assert from 'node:assert/strict';
import test from 'node:test';

import {
  QUICK_RETRY_MS,
  SYNC_LOOP_ANDROID_BACKGROUND_MS,
  SYNC_LOOP_DESKTOP_HIDDEN_MS,
  SYNC_LOOP_DESKTOP_LOW_BANDWIDTH_MS,
  SYNC_LOOP_ERROR_BACKOFF_MAX_MS,
  SYNC_LOOP_OFFLINE_MS,
  computeSyncCadenceDelay,
  shouldForceAndroidResumeResync,
} from '../../../app/src/lib/sync/cadence';

test('computeSyncCadenceDelay prioritizes quick retry and offline floors', () => {
  assert.equal(
    computeSyncCadenceDelay({
      mobilePlatform: 'unknown',
      online: true,
      visible: true,
      lowBandwidth: false,
      saveData: false,
      consecutiveErrorCount: 5,
      quickRetryRequested: true,
    }),
    QUICK_RETRY_MS,
  );

  assert.equal(
    computeSyncCadenceDelay({
      mobilePlatform: 'unknown',
      online: false,
      visible: true,
      lowBandwidth: false,
      saveData: false,
      consecutiveErrorCount: 0,
      quickRetryRequested: false,
    }),
    SYNC_LOOP_OFFLINE_MS,
  );
});

test('computeSyncCadenceDelay stretches desktop cadence for hidden and low-bandwidth windows', () => {
  assert.equal(
    computeSyncCadenceDelay({
      mobilePlatform: 'unknown',
      online: true,
      visible: false,
      lowBandwidth: false,
      saveData: false,
      consecutiveErrorCount: 0,
      quickRetryRequested: false,
    }),
    SYNC_LOOP_DESKTOP_HIDDEN_MS,
  );

  assert.equal(
    computeSyncCadenceDelay({
      mobilePlatform: 'unknown',
      online: true,
      visible: true,
      lowBandwidth: true,
      saveData: false,
      consecutiveErrorCount: 0,
      quickRetryRequested: false,
    }),
    SYNC_LOOP_DESKTOP_LOW_BANDWIDTH_MS,
  );
});

test('computeSyncCadenceDelay applies capped jittered backoff above the base cadence', () => {
  const originalRandom = Math.random;
  Math.random = () => 1;
  try {
    assert.equal(
      computeSyncCadenceDelay({
        mobilePlatform: 'unknown',
        online: true,
        visible: true,
        lowBandwidth: false,
        saveData: false,
        consecutiveErrorCount: 2,
        quickRetryRequested: false,
      }),
      66_000,
    );

    assert.equal(
      computeSyncCadenceDelay({
        mobilePlatform: 'android',
        online: true,
        visible: false,
        lowBandwidth: false,
        saveData: false,
        consecutiveErrorCount: 10,
        quickRetryRequested: false,
      }),
      Math.max(SYNC_LOOP_ANDROID_BACKGROUND_MS, SYNC_LOOP_ERROR_BACKOFF_MAX_MS * 1.1),
    );
  } finally {
    Math.random = originalRandom;
  }
});

test('computeSyncCadenceDelay honors mobile low-bandwidth floors even when active', () => {
  assert.equal(
    computeSyncCadenceDelay({
      mobilePlatform: 'android',
      online: true,
      visible: true,
      lowBandwidth: false,
      saveData: true,
      consecutiveErrorCount: 0,
      quickRetryRequested: false,
    }),
    240_000,
  );
});

test('shouldForceAndroidResumeResync only fires for visible android gaps above the threshold', () => {
  const now = Date.now();
  assert.equal(
    shouldForceAndroidResumeResync('android', now - SYNC_LOOP_ANDROID_BACKGROUND_MS, now, true),
    true,
  );
  assert.equal(
    shouldForceAndroidResumeResync('android', now - SYNC_LOOP_ANDROID_BACKGROUND_MS + 1, now, true),
    false,
  );
  assert.equal(
    shouldForceAndroidResumeResync('unknown', now - SYNC_LOOP_ANDROID_BACKGROUND_MS, now, true),
    false,
  );
  assert.equal(
    shouldForceAndroidResumeResync('android', now - SYNC_LOOP_ANDROID_BACKGROUND_MS, now, false),
    false,
  );
  assert.equal(
    shouldForceAndroidResumeResync('android', 0, now, true),
    false,
  );
});
