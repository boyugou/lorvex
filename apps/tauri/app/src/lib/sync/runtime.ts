import { useEffect } from 'react';

import { reportClientError } from '../errors/errorLogging';
import { extractNestedErrorMessage } from '../ipc/core.logic';
import { getRuntimeProfile, type MobilePlatform } from '../platform/platform';
import { getSyncBackendSupportContext } from '../syncBackend/model';
import { runSyncBackend } from '../syncBackend/runtime';

import {
  computeSyncCadenceDelay,
  DEFAULT_BATCH,
  MAX_CONSECUTIVE_REPULLS,
  QUICK_RETRY_MS,
} from './cadence';
import { createCadenceController } from './cadence_controller';
import { readNetworkCadenceHints } from './network';
import {
  loadResolvedBackgroundSyncPreferences,
  scheduleResolvedBackgroundSyncNormalization,
} from './preferences';
import { createBrowserBackgroundSyncBrowserHost } from './runtime.host';
import type { BackgroundSyncPendingWait } from './runtime.host';
import {
  createBackgroundSyncRuntimeController,
} from './runtime.logic';

function isNativeFunction(fn: unknown): fn is () => unknown {
  if (typeof fn !== 'function') return false;
  try {
    return /\{\s*\[native code\]\s*\}/.test(Function.prototype.toString.call(fn));
  } catch {
    return false;
  }
}

function readErrorStack(error: Error): string | undefined {
  const descriptor = Object.getOwnPropertyDescriptor(error, 'stack');
  if (!descriptor) return undefined;
  if ('value' in descriptor) {
    return typeof descriptor.value === 'string' && descriptor.value.trim()
      ? descriptor.value.trim()
      : undefined;
  }
  if (!isNativeFunction(descriptor.get)) return undefined;
  try {
    const stack = descriptor.get.call(error);
    return typeof stack === 'string' && stack.trim() ? stack.trim() : undefined;
  } catch {
    return undefined;
  }
}

export function syncTickErrorDetails(error: unknown): string | undefined {
  if (error instanceof Error) {
    const stack = readErrorStack(error);
    if (stack) return stack;
  }

  if (typeof error === 'object' && error != null) {
    const detail = extractNestedErrorMessage(error)?.trim();
    if (detail) {
      return detail;
    }
  }

  return undefined;
}

export function useBackgroundSyncBackend(enabled = true): void {
  useEffect(() => {
    if (!enabled) return;

    // Per-effect cancellation flag and running gate. Both live inside
    // the effect so a Settings → Sync `enabled` toggle (`true → false
    // → true`) starts the new cycle on a clean slate; an earlier
    // implementation hoisted `runningRef` outside the effect, which
    // let an old effect's in-flight `tick()` resolve into the new
    // effect's running gate and either wedge the loop or double-pull
    // for one cycle.
    let cancelled = false;
    let running = false;
    // every in-flight `wait()` setTimeout registers here
    // so the effect cleanup can cancel backoff timers instead of
    // letting them resolve post-unmount and re-enter stale closures.
    const pendingWaits = new Set<BackgroundSyncPendingWait>();
    const normalizationState = {
      normalizedSettings: false,
    };
    const runtimeProfile = getRuntimeProfile();
    const mobilePlatform: MobilePlatform = runtimeProfile.runtimeClass === 'mobile'
      ? runtimeProfile.runtimeId as MobilePlatform
      : 'unknown';
    const syncBackendSupport = getSyncBackendSupportContext(runtimeProfile);
    const browserHost = createBrowserBackgroundSyncBrowserHost();

    const resolveCadenceDelay = (quickRetryRequested: boolean): number => {
      const { lowBandwidth, saveData } = readNetworkCadenceHints();
      return computeSyncCadenceDelay({
        mobilePlatform,
        online: browserHost.isOnline(),
        visible: browserHost.isVisible(),
        lowBandwidth,
        saveData,
        consecutiveErrorCount: runtimeController.getConsecutiveErrorCount(),
        quickRetryRequested,
      });
    };

    const controller = createCadenceController({
      host: {
        now: () => Date.now(),
        isOnline: () => browserHost.isOnline(),
        setTimeout: (callback, delayMs) => browserHost.setTimeout(callback, delayMs),
        runTick: () => {
          if (cancelled) return;
          void tick();
        },
      },
      onResumeRequested: () => {
        runtimeController.handleCadenceResumeRequested(running);
      },
    });

    const schedule = (delayMs: number): void => {
      if (cancelled) return;
      controller.schedule(delayMs);
    };

    const runtimeController = createBackgroundSyncRuntimeController({
      host: {
        now: () => Date.now(),
        isVisible: () => browserHost.isVisible(),
        schedule,
      },
      mobilePlatform,
    });

    const tick = async () => {
      if (running) {
        schedule(resolveCadenceDelay(false));
        return;
      }

      running = true;
      let quickRetryRequested = false;
      try {
        if (browserHost.isOnline()) {
          const preferences = await loadResolvedBackgroundSyncPreferences({
            syncBackendSupport,
          });

          scheduleResolvedBackgroundSyncNormalization({
            settings: preferences.settings,
            normalizationState,
            shouldPersistNormalized: preferences.shouldPersistNormalized,
          });

          if (preferences.settings.enabled && preferences.activeBackend) {
            const result = await runSyncBackend({
              backend: preferences.activeBackend,
              maxEvents: DEFAULT_BATCH,
              maxConsecutiveRepulls: MAX_CONSECUTIVE_REPULLS,
              quickRetryMs: QUICK_RETRY_MS,
              isCancelled: () => cancelled,
              // track every backoff/retry timer so the
              // effect cleanup can cancel in-flight waits. Without
              // this, a 30 s backoff started just before unmount
              // resolves 30 s later and re-enters the caller's sync
              // loop on a stale closure.
              wait: (delayMs) => browserHost.wait(delayMs, () => cancelled, pendingWaits),
            });
            quickRetryRequested = result.quickRetryRequested;
            if (result.nextDelayOverrideMs != null) {
              schedule(runtimeController.consumeOverrideDelay(
                resolveCadenceDelay(quickRetryRequested),
                result.nextDelayOverrideMs,
              ));
              runtimeController.resetConsecutiveErrors();
              return;
            }
          }
        }
        runtimeController.resetConsecutiveErrors();
      } catch (err) {
        const details = syncTickErrorDetails(err);
        reportClientError('sync.background_loop', 'Background sync tick failed', err, details);
        // After 3 consecutive failures, warn the user once.
        if (runtimeController.recordTickError()) {
          // Resolve the toast locale via the user's persisted
          // PREF_LANGUAGE preference, falling back to
          // `detectSystemLocale()` only when no preference is set or
          // the stored value is malformed. The runtime has no React
          // context here, so it reads the raw preference through the
          // IPC wrapper and delegates to the canonical
          // `resolveLocalePreference` helper (the same one the
          // locale boot path uses), keeping a user's Settings
          // override authoritative over the OS locale.
          Promise.all([
            import('../notifications/toast'),
            import('@/locales/runtime'),
            import('../ipc/settings'),
            import('../preferences/keys'),
          ])
            .then(async ([
              { toast },
              { translate, resolveLocalePreference },
              { getPreference },
              { PREF_LANGUAGE },
            ]) => {
              let raw: string | null = null;
              try {
                raw = await getPreference(PREF_LANGUAGE);
              } catch (prefErr) {
                // Preference read failed; resolveLocalePreference's
                // null branch will fall through to detectSystemLocale,
                // which keeps the previous behaviour as a safety net.
                reportClientError(
                  'sync.repeated_failure_toast.read_locale_pref',
                  'Failed to read language preference for sync toast locale',
                  prefErr,
                  undefined,
                  'warn',
                );
              }
              const { locale } = resolveLocalePreference(raw);
              toast.error(translate(locale, 'sync.repeatedFailure'));
            })
            .catch((e) => {
              reportClientError(
                'sync.repeated_failure_toast',
                'Failed to show repeated-failure toast',
                e,
                undefined,
                'warn',
              );
            });
        }
      } finally {
        runtimeController.recordTickCompleted();
        running = false;
      }

      schedule(runtimeController.consumeNextDelay(resolveCadenceDelay(quickRetryRequested)));
    };

    const onWindowFocus = () => {
      // Don't trigger immediate sync on focus — this causes UI stutter
      // because a filesystem sync can hold the Tauri command thread.
      // The regular 60s cadence timer handles background sync.
      // Only reset the timer so the next tick happens sooner (but not instantly).
      runtimeController.handleWindowFocus(running);
    };
    const onVisibilityChange = () => {
      runtimeController.handleVisibilityChange(running);
    };
    const onPageShow = () => {
      runtimeController.handlePageShow(running);
    };
    const onResume = () => {
      runtimeController.handleResume(running);
    };
    // all three events flow through the cadence controller
    // so the online-gating + "back online, pull now" behavior lives in
    // one place and stays in sync with the logic tests.
    const onOnline = () => controller.handleOnline();
    const onOffline = () => controller.handleOffline();
    const onConnectionChange = () => controller.handleConnectionChange();
    const removeFocusListener = browserHost.addWindowListener('focus', onWindowFocus);
    const removePageShowListener = browserHost.addWindowListener('pageshow', onPageShow);
    const removeResumeListener = browserHost.addWindowListener('resume', onResume);
    const removeVisibilityListener = browserHost.addVisibilityListener(onVisibilityChange);
    const removeOnlineListener = browserHost.addWindowListener('online', onOnline);
    const removeOfflineListener = browserHost.addWindowListener('offline', onOffline);
    const removeConnectionListener = browserHost.addConnectionChangeListener(onConnectionChange);

    // delay the first tick by 2 s so it doesn't contend
    // with the main window's first-paint queries (getOverview,
    // getAllLists, native-calendar sync, widget snapshot export, and
    // the retention-cleanup IPC all fire on mount too). Filesystem
    // sync can easily burn 300–1500 ms on the
    // writer lock; deferring the first kick lets the user see the UI
    // paint before the sync loop starts. Subsequent cadence is
    // unchanged — only the cold-start path is debounced.
    runtimeController.scheduleInitialTick();
    return () => {
      cancelled = true;
      controller.dispose();
      // cancel any in-flight backoff/retry wait()
      // timers so their resolve callbacks don't re-enter the sync
      // loop after unmount. The `cancelled` flag above would prevent
      // any further work, but the Promise would still resolve and
      // propagate through `await wait(...)` — cheaper to clear.
      browserHost.clearPendingWaits(pendingWaits);
      removeConnectionListener();
      removeOfflineListener();
      removeOnlineListener();
      removeVisibilityListener();
      removeResumeListener();
      removePageShowListener();
      removeFocusListener();
    };
  }, [enabled]);
}
