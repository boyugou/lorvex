import type { MobilePlatform } from '../platform/platform';

/**
 * every cadence constant in this module lives on the
 * renderer's side of the wire — they govern how often
 * `useSyncCadenceController` re-arms its `setTimeout` loop, not the
 * backend's retry interval. The Rust transport has its own
 * exponential-backoff schedule for failed writes, and the two
 * schedules are intentionally independent: a renderer tick triggers
 * an outbox drain attempt; whether that attempt touches remote storage
 * is decided server-side.
 *
 * If you change a constant here, it has NO effect on the backend's
 * retry cadence. Conversely, if you tune the backend's backoff cap,
 * leave these alone unless the renderer-perceived freshness budget
 * is also part of the change.
 */

const SYNC_LOOP_DESKTOP_MS = 60_000;
// when the desktop window is hidden (other Space, app
// in background, screen locked), stretch the sync cadence so the
// sync loop doesn't wake the radio and hammer the SQLite writer
// every 60s. 5 min matches the SYNC_LOOP_OFFLINE_MS floor and is
// short enough that surfacing the window gives fresh data within
// ~seconds of the next resume tick.
export const SYNC_LOOP_DESKTOP_HIDDEN_MS = 300_000;
// Matches the mobile-low-bandwidth floor; applies on desktop too when
// the browser exposes saveData / effectiveType === slow-2g.
export const SYNC_LOOP_DESKTOP_LOW_BANDWIDTH_MS = 240_000;
const SYNC_LOOP_ANDROID_ACTIVE_MS = 120_000;
export const SYNC_LOOP_ANDROID_BACKGROUND_MS = 300_000;
const SYNC_LOOP_MOBILE_LOW_BANDWIDTH_MS = 240_000;
export const SYNC_LOOP_OFFLINE_MS = 300_000;
const SYNC_LOOP_ERROR_BACKOFF_BASE_MS = 30_000;
export const SYNC_LOOP_ERROR_BACKOFF_MAX_MS = 600_000;
export const QUICK_RETRY_MS = 2_000;
export const DEFAULT_BATCH = 50;
export const MAX_CONSECUTIVE_REPULLS = 5;
export const RESUME_RESYNC_THROTTLE_MS = 30_000;
const ANDROID_SUSPEND_RESYNC_GAP_MS = SYNC_LOOP_ANDROID_BACKGROUND_MS;

interface SyncCadenceInputs {
  mobilePlatform: MobilePlatform;
  online: boolean;
  visible: boolean;
  lowBandwidth: boolean;
  saveData: boolean;
  consecutiveErrorCount: number;
  quickRetryRequested: boolean;
}

export function computeSyncCadenceDelay(inputs: SyncCadenceInputs): number {
  if (inputs.quickRetryRequested) {
    return QUICK_RETRY_MS;
  }

  if (!inputs.online) {
    return SYNC_LOOP_OFFLINE_MS;
  }

  let cadenceMs = SYNC_LOOP_DESKTOP_MS;

  if (inputs.mobilePlatform === 'android') {
    cadenceMs = SYNC_LOOP_ANDROID_ACTIVE_MS;
    if (!inputs.visible) {
      cadenceMs = Math.max(cadenceMs, SYNC_LOOP_ANDROID_BACKGROUND_MS);
    }
  } else {
    // Desktop path (mobilePlatform === 'unknown'). When
    // the window is hidden or the network hints low-bandwidth,
    // stretch the cadence so the sync loop doesn't wake the radio /
    // hit the writer lock every minute for no benefit.
    if (!inputs.visible) {
      cadenceMs = Math.max(cadenceMs, SYNC_LOOP_DESKTOP_HIDDEN_MS);
    }
    if (inputs.lowBandwidth || inputs.saveData) {
      cadenceMs = Math.max(cadenceMs, SYNC_LOOP_DESKTOP_LOW_BANDWIDTH_MS);
    }
  }

  if (inputs.mobilePlatform !== 'unknown') {
    if (!inputs.visible) {
      cadenceMs = Math.max(cadenceMs, SYNC_LOOP_MOBILE_LOW_BANDWIDTH_MS);
    }
    if (inputs.lowBandwidth || inputs.saveData) {
      cadenceMs = Math.max(cadenceMs, SYNC_LOOP_MOBILE_LOW_BANDWIDTH_MS);
    }
  }

  if (inputs.consecutiveErrorCount > 0) {
    const backoffMs = Math.min(
      SYNC_LOOP_ERROR_BACKOFF_BASE_MS * Math.pow(2, inputs.consecutiveErrorCount - 1),
      SYNC_LOOP_ERROR_BACKOFF_MAX_MS,
    );
    // spread devices that entered error state within the
    // same 30s window across the retry boundary instead of hammering
    // the backend at identical (30s, 60s, 120s, …) marks. Mirrors the
    // jitter already applied on the Rust side for transport retries.
    cadenceMs = Math.max(cadenceMs, applySyncBackoffJitter(backoffMs));
  }

  return cadenceMs;
}

/// ±10% jitter using `Math.random()`. Multi-device setups hitting a
/// simultaneous transport outage no longer pile up at the same retry
/// instants; isolated call sites in tests can stub `Math.random` if
/// deterministic behavior is needed.
function applySyncBackoffJitter(baseMs: number): number {
  const factor = 0.9 + Math.random() * 0.2;
  return Math.max(0, baseMs * factor);
}

export function shouldForceAndroidResumeResync(
  mobilePlatform: MobilePlatform,
  lastTickCompletedAt: number,
  now: number,
  visible: boolean,
): boolean {
  if (mobilePlatform !== 'android') return false;
  if (!visible) return false;
  if (lastTickCompletedAt <= 0) return false;
  return now - lastTickCompletedAt >= ANDROID_SUSPEND_RESYNC_GAP_MS;
}
