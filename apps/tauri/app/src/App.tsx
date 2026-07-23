import { lazy, Suspense, useEffect, type ReactNode } from 'react';

import ErrorBoundary from './components/ErrorBoundary';
import ToastContainer from './components/ToastContainer';
import { ConfirmHost } from './components/ui/ConfirmDialog';
import { RecurrenceScopeHost } from './components/calendar/event-form/RecurrenceScopePicker';
import { ViewLoadingFallback } from './app-shell/support';

/**
 * Typed window-hash enum + dispatcher. Centralizing the hash literals
 * here (instead of inlining `window.location.hash === '#popover'`
 * checks at every callsite) keeps the set of known window kinds
 * exhaustive: a typo like `'#popver'` is a type error rather than a
 * silent route to the main-window default branch.
 */
const WINDOW_HASH = {
  popover: '#popover',
} as const;

type ResolvedWindow =
  | { kind: 'popover' }
  | { kind: 'main' };

function resolveWindowKind(hash: string): ResolvedWindow {
  if (hash === WINDOW_HASH.popover) return { kind: 'popover' };
  return { kind: 'main' };
}
import { reportClientError } from './lib/errors/errorLogging';
import { useI18n } from './lib/i18n';
import { installQuitFlushListener } from './lib/recovery/quitFlush';
import { useFontScaleApply } from './lib/useFontScale';
import { useRuntimeProfile } from './lib/useRuntimeProfile';
import { installAppRuntime } from './app.runtime';

const PopoverWindow = lazy(() => import('./components/PopoverWindow'));
// MainWindowApp was statically imported, which pulled
// its transitive graph (~200-300 kB gz: Sidebar, TodayView, sync
// runtime, notification hooks, widget bridge, Desktop+Mobile shells,
// chrono-node via QuickCapture, etc.) into EVERY window's initial
// bundle — including popover/focus that never mount
// it. Switch to lazy() so each secondary window only ships its
// own subtree.
const MainWindowApp = lazy(() =>
  import('./app-shell/MainWindowApp').then((m) => ({ default: m.MainWindowApp })),
);

/**
 * All four window-kind branches wrap their lazy view in
 * `ErrorBoundary > Suspense`, then mount `<ConfirmHost />` (and, for
 * the secondary windows that own a full container, also
 * `<ToastContainer />`). Centralizing the shell here makes the order
 * — and the required hosts — invariant, so a future branch can never
 * invert `ErrorBoundary`/`Suspense` or move `<ConfirmHost />` inside
 * `Suspense` by accident.
 *
 * `wrapperClass` is empty for the popover/main shells (which are
 * fragments — no full-bleed container) and a `h-full bg-…` for the
 * secondary windows that own their entire viewport. `includeToast`
 * is `false` for popover/main (the main window's `ToastContainer`
 * lives inside `MainWindowApp`; popover has no toast surface).
 */
interface WindowShellProps {
  wrapperClass?: string;
  includeToast: boolean;
  /**
   * when set, wrap the rendered view in a
   * `<main id="main-content">` landmark so SR users have a primary
   * landmark to jump to in secondary windows (Settings / Focus /
   * Popover). The desktop + mobile main-window shells already
   * own their own `<main>` (DesktopMainWindow.tsx / MobileMainWindow.tsx),
   * so the main-window branch passes `mainLandmark={false}` to avoid
   * nesting two `<main>` elements.
   */
  mainLandmark?: boolean;
  /** Accessible name for the `<main>` landmark when `mainLandmark` is set. */
  mainLandmarkLabel?: string;
  children: ReactNode;
}

function WindowShell({ wrapperClass, includeToast, mainLandmark = false, mainLandmarkLabel, children }: WindowShellProps) {
  // ErrorBoundary wraps Suspense so a rejected lazy import (chunk-load
  // failure, transitive import error, etc.) is caught by the boundary
  // and renders a fallback. Inverting this — boundary INSIDE Suspense —
  // lets the rejection blow past the boundary and white-screen the
  // window. Route the lazy subtree through a `<main>`
  // landmark when the caller opted in. Secondary windows had no
  // `<main>`, so SR users on Focus / Popover had
  // no landmark to skip into. The wrapper is `h-full` so it inherits
  // the secondary window's full-bleed sizing; without that the
  // `<section>` children that rely on `h-full` collapsed to content
  // height (the focus panel uses `desktop-card` with
  // an absolute-positioned background that needs the parent height).
  const view = mainLandmark ? (
    <main
      id="main-content"
      aria-label={mainLandmarkLabel}
      className="h-full"
    >
      <ErrorBoundary>
        <Suspense fallback={<ViewLoadingFallback />}>
          {children}
        </Suspense>
      </ErrorBoundary>
    </main>
  ) : (
    <ErrorBoundary>
      <Suspense fallback={<ViewLoadingFallback />}>
        {children}
      </Suspense>
    </ErrorBoundary>
  );
  const inner = (
    <>
      {view}
      <ConfirmHost />
      <RecurrenceScopeHost />
      {includeToast && <ToastContainer />}
    </>
  );
  if (!wrapperClass) return inner;
  return <div className={wrapperClass}>{inner}</div>;
}

function PopoverWindowApp() {
  const { t } = useI18n();
  // PopoverWindowContent fires `toast.errorWithDetail(...)` from
  // at least three interaction paths (open task, complete, defer).
  // Without a ToastContainer mounted in this
  // webview those toasts had nowhere to render — silent failures. The
  // popover is its own webview, so the main-window's ToastContainer
  // does not cover it. Mount one here.
  return (
    <WindowShell
      includeToast
      mainLandmark
      mainLandmarkLabel={t('popover.title')}
    >
      <PopoverWindow />
    </WindowShell>
  );
}

export default function App() {
  const runtimeProfile = useRuntimeProfile();
  // Apply user's font scale to ALL windows (main, popover, focus).
  // Side-effect-only variant — the read/write API in `useFontScale` is
  // for the settings UI, not the app shell.
  useFontScaleApply();

  useEffect(() => {
    // install the global quit-flush listener so
    // controllers that registered debounced-write flush callbacks
    // actually run before `app_handle.exit(0)` tears down the
    // webview process.
    const runtime = installAppRuntime({
      installQuitFlushListener,
      reportClientError,
      windowTarget: window,
    });
    return runtime.cleanup;
  }, []);

  // every window kind shares the same shell —
  // `<div className={bg}>{ErrorBoundary>Suspense>view}</div>` plus
  // `<ConfirmHost />` and (in non-main shells) `<ToastContainer />`.
  // Standardize via `WindowShell` so a future shell change can't drift
  // (-L2 was a regression of exactly this asymmetry where the
  // popover branch put `<ConfirmHost />` INSIDE Suspense + inverted
  // the ErrorBoundary/Suspense order — both classes of bug now live
  // in one place that's hard to reintroduce).
  const resolved = resolveWindowKind(window.location.hash);
  switch (resolved.kind) {
    case 'popover':
      return <PopoverWindowApp />;
    case 'main':
      // Fall through to the main-window render at the bottom.
      break;
  }

  return (
    <WindowShell includeToast={false}>
      <MainWindowApp runtimeProfile={runtimeProfile} />
    </WindowShell>
  );
}
