import { lazy, Suspense, useCallback, useEffect } from 'react';

import ToastContainer from '../components/ToastContainer';
import Announcer from '../components/ui/Announcer';
import { NotificationPermissionBanner } from '../components/ui/NotificationPermissionBanner';
import { reportClientError } from '../lib/errors/errorLogging';
import { useI18n } from '../lib/i18n';
import { runDataRetentionCleanup } from '@/lib/ipc/settings';
import {
  useAtRiskNotifications,
  useNativeCalendarAutoSync,
  useNotificationPermissionPrompt,
  useNotificationPermissionStatus,
  useReminderNotifications,
  useScheduledNotifications,
} from '../lib/notifications/usePollingNotifications';
import type { RuntimeProfile } from '../lib/platform/platform';
import { useBackgroundSyncBackend } from '../lib/sync/runtime';
import { useVisibilityGatedInterval } from '../lib/time/useVisibilityGatedInterval';
import { ViewLoadingFallback } from './support';

import { DesktopMainWindow } from './main-window/DesktopMainWindow';
import { MobileMainWindow } from './main-window/MobileMainWindow';
import {
  createBrowserMainWindowPrefetchHost,
  installMainWindowPrefetchRuntime,
} from './main-window/runtime/useMainWindowPrefetch.runtime';
import { useMainWindowController } from './main-window/useMainWindowController';
import { HOUR_MS } from '@/lib/time/durations';

// QuickCapture and CommandPalette must feel
// instant on first open, but the prior pattern fired the dynamic
// imports at module scope — before first paint. QuickCapture's
// chrono-node + 13 locale parsers (~120 kB gz) were pulled into the
// main-window critical path.
//
// New strategy: keep lazy() but have the imports be lazily triggered
// only when `MainWindowApp` itself mounts. This still beats a JIT
// user click (the chunk downloads in parallel with first paint) but
// removes the module-scope side effect, and keeps the chunk off
// secondary-window surfaces entirely (popover, focus) since
// those never mount MainWindowApp.
const QuickCapture = lazy(() => import('../components/QuickCapture'));
const CommandPalette = lazy(() => import('../components/CommandPalette'));
const mainWindowPrefetchHost = createBrowserMainWindowPrefetchHost();

interface MainWindowAppProps {
  runtimeProfile: RuntimeProfile;
}

export function MainWindowApp({ runtimeProfile }: MainWindowAppProps) {
  const usesMobileLayout = runtimeProfile.runtimeClass === 'mobile';
  const controller = useMainWindowController(runtimeProfile);
  const {
    activeCommandPaletteSession,
    activeQuickCaptureSession,
    closeCommandPalette,
    closeQuickCapture,
    handleSidebarNavigate,
    lists,
    openQuickCapture,
    quickCaptureInitialData,
    showCapture,
    showPalette,
    startMainWindowDragging,
    toggleMainWindowZoom,
  } = controller;

  useReminderNotifications();
  useScheduledNotifications();
  useAtRiskNotifications(!usesMobileLayout);
  useNotificationPermissionPrompt(!usesMobileLayout);
  // status-probe is independent of the first-run prompt
  // hook — it re-checks on every window focus so a user who revokes
  // in System Settings while Lorvex is running sees the banner on
  // next focus.
  const { promptedButDenied, requestAgain } = useNotificationPermissionStatus(!usesMobileLayout);
  const { t } = useI18n();
  useNativeCalendarAutoSync(runtimeProfile);
  useBackgroundSyncBackend(runtimeProfile.supportsBackgroundSync);
  const runCleanup = useCallback(() => {
    void runDataRetentionCleanup().catch((e) => {
      // Route retention-cleanup failures through `error_logs` so
      // Settings → Diagnostics surfaces them. Use `'warn'` severity
      // since a single missed pass isn't user-blocking; the next
      // visibility flip catches up.
      reportClientError(
        'app.runDataRetentionCleanup',
        'Data retention cleanup failed',
        e,
        undefined,
        'warn',
      );
    });
  }, []);

  const SIX_HOURS_MS = 6 * HOUR_MS;
  useVisibilityGatedInterval(runCleanup, SIX_HOURS_MS);

  // warm caches for heavy on-demand views AFTER first
  // paint. requestIdleCallback (where available) yields the main
  // thread entirely; setTimeout(0) is a reasonable fallback. These
  // live inside the main-window component so secondary windows
  // (popover, focus) never touch the prefetch at all.
  //
  // gate the prefetch on `!usesMobileLayout`. Mobile
  // surfaces never render `AllTasksView` / `UpcomingView` / `ListView`
  // at all (they have their own swipe-driven shell), so warming
  // those bundles on a phone is pure overhead — extra disk reads,
  // extra JS-VM compile, slower TTI for the views the user actually
  // sees. Desktop is unaffected.
  useEffect(() => {
    if (usesMobileLayout) return;
    const handle = installMainWindowPrefetchRuntime({
      fallbackDelayMs: 0,
      prefetch: () => {
        void import('../components/AllTasksView');
        void import('../components/UpcomingView');
        void import('../components/ListView');
      },
      ...mainWindowPrefetchHost,
    });
    return handle.dispose;
  }, [usesMobileLayout]);

  return (
    <Suspense fallback={<ViewLoadingFallback />}>
      {/* Tauri window-drag region: onMouseDown initiates native window
          drag, onDoubleClick toggles zoom. These are window-chrome
          affordances — not user-action targets — so a button role +
          keyboard listener would mis-describe the contract. The native
          OS provides its own keyboard window-management chord
          (Ctrl+Cmd+F maximize, etc.) outside of React's purview. */}
      {/* eslint-disable-next-line jsx-a11y/no-static-element-interactions */}
      <div
        className={`h-full bg-surface-0 ${usesMobileLayout ? 'flex flex-col' : 'desktop-shell flex gap-3 p-2.5 pt-0.5'}`}
        onMouseDown={(event) => {
          if (usesMobileLayout || event.button !== 0) return;
          if (event.target === event.currentTarget) {
            startMainWindowDragging();
          }
        }}
        onDoubleClick={(event) => {
          if (usesMobileLayout) return;
          if (event.target === event.currentTarget) {
            void toggleMainWindowZoom();
          }
        }}
      >
        {usesMobileLayout ? (
          <MobileMainWindow controller={controller} />
        ) : (
          <DesktopMainWindow controller={controller} />
        )}

        {showCapture && activeQuickCaptureSession != null && (
          <Suspense fallback={null}>
            <QuickCapture
              key={activeQuickCaptureSession}
              lists={lists}
              isMobile={usesMobileLayout}
              onClose={() => closeQuickCapture(activeQuickCaptureSession)}
              initialData={quickCaptureInitialData}
              sessionId={activeQuickCaptureSession}
              onReopenForRetry={(draft) => openQuickCapture(draft)}
            />
          </Suspense>
        )}

        {promptedButDenied && (
          <div className="fixed top-2 start-2.5 end-2.5 z-[var(--z-overlay)] pointer-events-none">
            <div className="pointer-events-auto max-w-2xl mx-auto">
              <NotificationPermissionBanner t={t} onRequestAgain={requestAgain} />
            </div>
          </div>
        )}

        <ToastContainer />
        <Announcer />

        {!usesMobileLayout && showPalette && activeCommandPaletteSession != null && (
          <Suspense fallback={null}>
            <CommandPalette
              onClose={() => closeCommandPalette(activeCommandPaletteSession)}
              onNavigate={handleSidebarNavigate}
              onSelectTask={controller.onSelectTask}
              onQuickCapture={openQuickCapture}
            />
          </Suspense>
        )}
      </div>
    </Suspense>
  );
}
