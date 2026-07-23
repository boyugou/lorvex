import { useCallback, useEffect, useRef, useState } from 'react';
import { listen } from '@tauri-apps/api/event';

import ErrorBoundary from '@/components/ErrorBoundary';
import { useI18n } from '@/lib/i18n';
import { reportClientError } from '@/lib/errors/errorLogging';
import { KeyboardShortcutsPanel } from '@/components/keyboard-shortcuts';
import MainViewContent from '@/components/MainViewContent';
import Sidebar from '@/components/Sidebar';
import TaskDetail from '@/components/TaskDetail';
import { SlidePanel } from '@/components/ui/SlidePanel';
import {
  dispatchEditorHistoryShortcut,
  isEditorHistoryShortcutTarget,
} from '@/lib/shortcuts/editorHistory';
import {
  getHistoryShortcutAction,
  resolveHistoryShortcutRoute,
  resolveUnhandledEditorHistoryShortcutRoute,
} from '@/lib/historyShortcuts.logic';
import { getRuntimeProfile } from '@/lib/platform/platform';
import { shouldIgnoreChordShortcut, shouldIgnoreShortcut } from '@/lib/shortcutGuard';
import { triggerLatestUndo } from '@/lib/notifications/toast';
import { createAsyncTauriListenerScope } from '@/lib/tauriListenerLifecycle';
import { useCalendarSubscriptionSync } from '@/lib/calendarSubscriptionSync';

const runtimeProfile = getRuntimeProfile();

import type { MainWindowController } from './types';

interface DesktopMainWindowProps {
  controller: MainWindowController;
}

function runNativeHistoryAction(action: 'undo' | 'redo'): void {
  try {
    document.execCommand(action);
  } catch {
    // Older browsers may throw; there is no equivalent fallback for
    // native input history.
  }
}

export function DesktopMainWindow({ controller }: DesktopMainWindowProps) {
  const { t } = useI18n();
  useCalendarSubscriptionSync();
  const [showShortcuts, setShowShortcuts] = useState(false);
  // SlidePanel moves focus here when the task-detail side
  // panel opens, so a keyboard user landing on the panel starts in the
  // primary editable field instead of the panel container.
  const taskDetailTitleRef = useRef<HTMLInputElement | null>(null);
  // The TaskDetail controller writes its persistDrafts callback into this
  // ref on mount. Every parent-owned close path (the X button rendered
  // by TaskDetail's own header, the ErrorBoundary fallback
  // close button) routes through `closeTaskDetail` below so unsaved drafts
  // are flushed before the panel tears down. Without this, those paths
  // called setSelectedTaskId(null) directly and silently dropped unsaved
  // edits even when the underlying save failed (UX bug U5).
  const taskDetailFlushDraftsRef = useRef<(() => Promise<boolean>) | null>(null);
  const toggleShortcuts = useCallback(() => setShowShortcuts((prev) => !prev), []);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      // identify the `?` keystroke by KeyboardEvent.code,
      // not the printable `event.key`. On non-US layouts (e.g. AZERTY,
      // QWERTZ, Dvorak) the `?` glyph lives on a different physical
      // key so `event.key === '?'` either misses the chord entirely
      // or — worse — triggers on an unrelated dead-key sequence. The
      // physical Slash key is stable across layouts; the user's
      // muscle-memory chord is Shift+Slash regardless of glyph.
      //
      // The shouldIgnoreShortcut + IME-composition gates run BEFORE
      // the printable-key match, so a Pinyin composition that
      // synthesizes a Slash punctuation candidate mid-IME does not
      // toggle the shortcuts panel.
      if (
        event.code === 'Slash'
        && event.shiftKey
        && !event.metaKey
        && !event.ctrlKey
        && !event.altKey
      ) {
        if (shouldIgnoreShortcut(event.target)) return;
        if (event.isComposing) return;
        event.preventDefault();
        toggleShortcuts();
        return;
      }
      const historyAction = getHistoryShortcutAction(event);
      if (!historyAction || event.defaultPrevented) return;

      const historyTarget = event.target ?? document.activeElement;
      // history is a chord shortcut (⌘Z / ⌘⇧Z / ⌘Y),
      // so use `shouldIgnoreChordShortcut` — that lets the shortcut
      // reach the toast/native router from inside a confirm dialog
      // or popover (the user expects ⌘Z to undo regardless of which
      // overlay is on screen, as long as they aren't typing in a
      // text field). The bare-key `?` shortcut above still uses the
      // strict `shouldIgnoreShortcut` because it would be intrusive
      // to fire while a confirm prompt is being read.
      const route = resolveHistoryShortcutRoute({
        action: historyAction,
        activeElementIgnoresShortcut: shouldIgnoreChordShortcut(document.activeElement),
        editorOwnsTarget:
          isEditorHistoryShortcutTarget(historyTarget)
          || isEditorHistoryShortcutTarget(document.activeElement),
        targetIgnoresShortcut: shouldIgnoreChordShortcut(event.target),
      });

      if (route === 'editor') {
        if (dispatchEditorHistoryShortcut(historyAction, historyTarget)) {
          event.preventDefault();
          return;
        }
        if (
          resolveUnhandledEditorHistoryShortcutRoute(historyAction) === 'toast'
          && triggerLatestUndo()
        ) {
          event.preventDefault();
        }
        return;
      }
      if (route === 'native') {
        event.preventDefault();
        runNativeHistoryAction(historyAction);
        return;
      }
      if (route === 'toast' && triggerLatestUndo()) {
        event.preventDefault();
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [toggleShortcuts]);

  // Help menu → Keyboard Shortcuts routes through
  // `menu://open-shortcuts` so the same panel the `?` shortcut
  // opens is reachable from the menu bar without adding a second
  // component-level piece of state.
  useEffect(() => {
    const listeners = createAsyncTauriListenerScope();
    let cancelled = false;

    listeners.add(
      listen('menu://open-shortcuts', () => {
        if (cancelled) return;
        setShowShortcuts(true);
      }),
      (error) => {
        reportClientError(
          'menu.openShortcuts',
          'Failed to listen for keyboard-shortcuts menu events',
          error,
        );
      },
    );

    return () => {
      cancelled = true;
      listeners.dispose();
    };
  }, []);

  const {
    handleSidebarNavigate,
    isOverviewError,
    lists,
    navigateToView,
    onRetryOverview,
    onSelectTask,
    openCommandPalette,
    openQuickCapture,
    overview,
    selectedTaskId,
    setSelectedTaskId,
    startMainWindowDragging,
    usesMobileLayout,
    view,
  } = controller;

  // Single close path for the task-detail SlidePanel — flushes unsaved
  // drafts via the ref the controller publishes, and only clears the
  // selection if the flush succeeds (so a save error keeps the panel open
  // for the user to retry instead of dropping their edits).
  const closeTaskDetail = useCallback(() => {
    const flush = taskDetailFlushDraftsRef.current;
    if (!flush) {
      // No controller mounted (e.g. ErrorBoundary tripped before drafts
      // initialized). Falling through to the bare setter is safe — there
      // are no drafts to lose.
      setSelectedTaskId(null);
      return;
    }
    void flush().then((ok) => {
      if (ok) setSelectedTaskId(null);
    });
  }, [setSelectedTaskId]);

  return (
    <>
      {/* skip-link must out-stack ANY surface
          (including modals + toasts) so a keyboard-only user can
          always bail back to main content — pin it to the
          --z-critical tier (80) instead of the bare `focus:z-50`,
          which would have been buried behind any open modal
          (--z-modal = 60) or toast (--z-toast = 70). */}
      <a
        href="#main-content"
        className="sr-only focus:not-sr-only focus:absolute focus:z-[var(--z-critical)] focus:top-2 focus:start-2 focus:px-3 focus:py-1.5 focus:bg-surface-2 focus:text-text-primary focus:rounded-r-card focus:text-xs focus:shadow-[var(--shadow-popover)] focus-ring-soft"
      >
        {t('common.skipToMain')}
      </a>
      <div className="desktop-card w-56 shrink-0 flex flex-col overflow-hidden">
        <Sidebar
          lists={lists}
          stats={overview?.stats ?? null}
          currentView={view}
          onNavigate={handleSidebarNavigate}
          onQuickCapture={openQuickCapture}
          onOpenPalette={openCommandPalette}
          onWindowDragStart={startMainWindowDragging}
          usesMobileLayout={usesMobileLayout}
        />
      </div>

      <section className="flex-1 min-w-0 flex flex-col overflow-hidden bg-surface-0">
        {runtimeProfile.supportsTitleBarOverlay && (
          // Tauri title-bar overlay drag region. onMouseDown is wired
          // for native window-drag forwarding; this is window chrome,
          // not a user-action target, so jsx-a11y's "give it a role
          // and keyboard handler" guidance does not apply.
          // eslint-disable-next-line jsx-a11y/no-static-element-interactions
          <div
            className="h-7 shrink-0 relative flex items-center justify-end gap-1"
            data-tauri-drag-region
            onMouseDown={(event) => { if (event.button === 0) startMainWindowDragging(); }}
          />
        )}
        <div className="min-h-0 flex-1">
          <main id="main-content" className="h-full overflow-hidden">
            {/* single application-level `<h1>` so the
                document outline starts at exactly one h1. Each view
                renders its own visible heading as `<h2>` (audit notes
                pre-fix used `<h1>` per view, which produced 10+ h1s in
                the SR heading list and blurred the document outline).
                The h1 stays sr-only because the visible chrome already
                identifies the brand via window title + sidebar. */}
            <h1 className="sr-only">Lorvex</h1>
            <MainViewContent
              view={view}
              overview={overview}
              onSelectTask={onSelectTask}
              onNavigate={navigateToView}
              onOpenQuickCapture={() => openQuickCapture()}
              isOverviewError={isOverviewError}
              onRetryOverview={onRetryOverview}
            />
          </main>
        </div>
      </section>

      {/* Task detail panel spans full window height (including titlebar area).: SlidePanel owns a11y semantics — renders as
          role="complementary", focuses the title input on open, and
          restores focus to the originating list row on close. We
          deliberately do NOT promote it to role="dialog"/aria-modal
          because the panel coexists with the background list; promoting
          it would steal background clicks from the list it augments. */}
      <SlidePanel
        open={selectedTaskId !== null}
        ariaLabel={t('taskDetail.panelLabel')}
        initialFocusRef={taskDetailTitleRef}
        className="w-96 shrink-0 shadow-[var(--shadow-rail-edge)]"
          >
            {selectedTaskId !== null && (
              <ErrorBoundary
                resetKeys={[selectedTaskId]}
                fallback={
                  <div className="flex flex-col items-center justify-center h-full px-4 sm:px-8 text-center gap-3">
                    <p className="text-text-secondary text-sm">{t('error.message')}</p>
                    <button
                      type="button"
                      onClick={closeTaskDetail}
                      className="text-sm text-accent hover:text-accent/80 transition-colors"
                    >
                      {t('common.close')}
                    </button>
                  </div>
                }
              >
                <TaskDetail
                  taskId={selectedTaskId}
                  onClose={closeTaskDetail}
                  onSelectTask={setSelectedTaskId}
                  titleRef={taskDetailTitleRef}
                  flushDraftsRef={taskDetailFlushDraftsRef}
                />
              </ErrorBoundary>
            )}
          </SlidePanel>

      {showShortcuts && (
        <KeyboardShortcutsPanel onClose={() => setShowShortcuts(false)} />
      )}
    </>
  );
}
