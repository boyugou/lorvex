import { listen } from '@/lib/platform/events';
import { getCurrentWindow } from '@/lib/platform/window';
import { useCallback, useEffect, useRef } from 'react';

import { reportClientError } from '@/lib/errors/errorLogging';
import { hidePopoverWindow } from '@/lib/ipc/runtime';
import { createAsyncTauriListenerScope } from '@/lib/tauriListenerLifecycle';
import {
  clearPopoverPendingHideTimer,
  createBrowserPopoverPendingHideTimerHost,
  schedulePopoverPendingHide,
} from './lifecycle.runtime';
import type { UsePopoverWindowLifecycleArgs } from './types';

const windowHandle = getCurrentWindow();
const INITIAL_BLUR_GUARD_MS = 700;
const OPENED_BLUR_GUARD_MS = 1_200;
const BLUR_WITHOUT_FOCUS_GRACE_MS = 10_000;
const PENDING_HIDE_DELAY_MS = 160;
const FOCUS_BLUR_GUARD_MS = 400;
const popoverPendingHideTimerHost = createBrowserPopoverPendingHideTimerHost();

export function usePopoverWindowLifecycle({
  loadSummary,
}: UsePopoverWindowLifecycleArgs): { requestHidePopover: () => Promise<void> } {
  const ignoreBlurUntilRef = useRef(0);
  const focusedSinceOpenRef = useRef(false);
  const allowBlurWithoutFocusAtRef = useRef(0);
  const pendingHideTimerRef = useRef<number | null>(null);
  // Ref-stash `loadSummary` so the listener-install effect can depend
  // on the ref alone — otherwise the daily `dayContext.todayYmd` flip
  // changes the `loadSummary` identity, the effect tears down at
  // midnight, and `tauri://blur/focus`/`tray://popover-opened` events
  // arriving in the gap are dropped.
  const loadSummaryRef = useRef(loadSummary);
  loadSummaryRef.current = loadSummary;

  // Grace timers use `performance.now()` — a monotonic clock that is
  // unaffected by system clock backsync. Wall-clock `Date.now()`
  // would erroneously short-circuit (or delay forever) blur guards if the
  // OS resyncs while the popover is open.
  const armBlurGuard = useCallback((ms: number) => {
    ignoreBlurUntilRef.current = performance.now() + ms;
  }, []);

  const clearPendingHide = useCallback(() => {
    clearPopoverPendingHideTimer(pendingHideTimerRef, popoverPendingHideTimerHost);
  }, []);

  const requestHidePopover = useCallback(() => hidePopoverWindow().catch((error) => {
    reportClientError('popover.hide', 'Failed to hide popover', error);
  }), []);

  useEffect(() => {
    armBlurGuard(INITIAL_BLUR_GUARD_MS);
  }, [armBlurGuard]);

  useEffect(() => {
    const listeners = createAsyncTauriListenerScope();

    const onOpened = () => {
      clearPendingHide();
      focusedSinceOpenRef.current = false;
      allowBlurWithoutFocusAtRef.current = performance.now() + BLUR_WITHOUT_FOCUS_GRACE_MS;
      armBlurGuard(OPENED_BLUR_GUARD_MS);
      void loadSummaryRef.current(false);
    };

    listeners.add(
      listen('tauri://blur', () => {
        if (performance.now() < ignoreBlurUntilRef.current) return;
        if (!focusedSinceOpenRef.current && performance.now() < allowBlurWithoutFocusAtRef.current) return;
        schedulePopoverPendingHide(
          pendingHideTimerRef,
          popoverPendingHideTimerHost,
          PENDING_HIDE_DELAY_MS,
          () => {
            if (performance.now() < ignoreBlurUntilRef.current) return;
            void windowHandle
              .isFocused()
              .then((isFocused) => {
                if (!isFocused) {
                  return requestHidePopover();
                }
                return undefined;
              })
              .catch(() => {
                void requestHidePopover();
              });
          },
        );
      }),
      (error) => {
        reportClientError('popover.listenBlur', 'Failed to subscribe to popover blur events', error);
      },
    );

    listeners.add(
      listen('tauri://focus', () => {
        clearPendingHide();
        focusedSinceOpenRef.current = true;
        armBlurGuard(FOCUS_BLUR_GUARD_MS);
        void loadSummaryRef.current(false);
      }),
      (error) => {
        reportClientError('popover.listenFocus', 'Failed to subscribe to popover focus events', error);
      },
    );

    listeners.add(
      listen('tray://popover-opened', onOpened),
      (error) => {
        reportClientError('popover.listenOpened', 'Failed to subscribe to tray popover events', error);
      },
    );

    return () => {
      listeners.dispose();
      clearPendingHide();
    };
  }, [armBlurGuard, clearPendingHide, requestHidePopover]);

  return { requestHidePopover };
}
