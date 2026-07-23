import { getRuntimeProfile } from '../platform/platform';

const SYNC_LOOP_DESKTOP_MS = 60_000;
const SYNC_LOOP_ANDROID_ACTIVE_MS = 120_000;
const SYNC_LOOP_ANDROID_BACKGROUND_MS = 300_000;
const SYNC_LOOP_MOBILE_LOW_BANDWIDTH_MS = 240_000;
const SYNC_LOOP_OFFLINE_MS = 300_000;
const SYNC_LOOP_ERROR_BACKOFF_BASE_MS = 30_000;
const SYNC_LOOP_ERROR_BACKOFF_MAX_MS = 600_000;

interface Inputs {
  mobilePlatform: string;
  online: boolean;
  visible: boolean;
  lowBandwidth: boolean;
  saveData: boolean;
  consecutiveErrorCount: number;
}

function computeSyncCadenceDelay(inputs: Inputs): number {
  let cadenceMs = SYNC_LOOP_DESKTOP_MS;
  if (inputs.mobilePlatform === 'android') {
    cadenceMs = SYNC_LOOP_ANDROID_ACTIVE_MS;
    if (!inputs.visible) cadenceMs = Math.max(cadenceMs, SYNC_LOOP_ANDROID_BACKGROUND_MS);
  }
  if (!inputs.online) cadenceMs = SYNC_LOOP_OFFLINE_MS;
  if (inputs.lowBandwidth || inputs.saveData) cadenceMs = Math.max(cadenceMs, SYNC_LOOP_MOBILE_LOW_BANDWIDTH_MS);
  if (inputs.consecutiveErrorCount > 0) {
    cadenceMs = Math.max(cadenceMs, Math.min(SYNC_LOOP_ERROR_BACKOFF_BASE_MS * Math.pow(2, inputs.consecutiveErrorCount - 1), SYNC_LOOP_ERROR_BACKOFF_MAX_MS));
  }
  return cadenceMs;
}

export function startSyncLoop(): void {
  const caps = getRuntimeProfile();
  const online = navigator.onLine;
  const connection = (navigator as Navigator & { connection?: { effectiveType?: string; saveData?: boolean } }).connection;
  const effectiveType = connection?.effectiveType ?? '';
  const saveData = Boolean(connection?.saveData);
  void computeSyncCadenceDelay({
    mobilePlatform: caps.mobilePlatform,
    online,
    visible: document.visibilityState === 'visible',
    lowBandwidth: effectiveType === '2g',
    saveData,
    consecutiveErrorCount: 1,
  });

  window.addEventListener('online', () => {});
  window.addEventListener('offline', () => {});
}
