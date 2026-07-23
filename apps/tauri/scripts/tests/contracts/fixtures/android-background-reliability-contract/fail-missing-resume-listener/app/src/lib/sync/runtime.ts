const SYNC_LOOP_ANDROID_BACKGROUND_MS = 300_000;
const ANDROID_SUSPEND_RESYNC_GAP_MS = SYNC_LOOP_ANDROID_BACKGROUND_MS;

function shouldForceAndroidResumeResync() {
  return true;
}

function scheduleImmediateTick(_force?: boolean) {}

function onPageShow() {
  if (shouldForceAndroidResumeResync()) {
    scheduleImmediateTick(true);
  }
}

window.addEventListener('pageshow', onPageShow);
