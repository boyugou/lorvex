import { lazy, type ReactNode, Suspense, useCallback, useEffect, useMemo, useRef } from 'react';
import type { Overview } from '@/lib/ipc/tasks/models';
import type { View } from '../lib/types';
import type { QuickCaptureInitialData } from '../app-shell/main-window/types';
import { useI18n, type TranslationKey } from '../lib/i18n';
import { announce } from '../lib/announce';
import { formatPageTitle } from '../lib/pageTitle';
import ErrorBoundary from './ErrorBoundary';
import SettingsView from './SettingsView.lazy';
import TodayView from './TodayView';
import { ViewLoadingFallback } from '../app-shell/support';
import { ChangelogSkeleton } from './changelog/ChangelogSkeleton';

const ListView = lazy(() => import('./ListView'));
const ChangelogView = lazy(() => import('./ChangelogView'));
const SomedayView = lazy(() => import('./SomedayView'));
const UpcomingView = lazy(() => import('./UpcomingView'));
const AllTasksView = lazy(() => import('./AllTasksView'));
const AIMemoryView = lazy(() => import('./ai-memory/AIMemoryView'));
const WeeklyReviewView = lazy(() => import('./WeeklyReviewView'));
const DailyReviewView = lazy(() => import('./DailyReviewView'));
const CalendarView = lazy(() => import('./CalendarView'));
const EisenhowerView = lazy(() => import('./EisenhowerView'));
const KanbanView = lazy(() => import('./KanbanView'));
const DependencyGraphView = lazy(() => import('./DependencyGraphView'));
const HabitsView = lazy(() => import('./HabitsView'));
const RecurringTasksView = lazy(() => import('./RecurringTasksView'));

// ---------------------------------------------------------------------------
// Per-view error + suspense boundary
// ---------------------------------------------------------------------------

function ViewBoundary({ resetKeys, children }: { resetKeys: ReadonlyArray<unknown>; children: ReactNode }) {
  return (
    <ErrorBoundary resetKeys={resetKeys}>
      <Suspense fallback={<ViewLoadingFallback />}>
        <div className="h-full animate-[fade-in_0.15s_ease-out]">
          {children}
        </div>
      </Suspense>
    </ErrorBoundary>
  );
}

// ---------------------------------------------------------------------------
// View-type → translation key map for SR page-title announcements.
// when the user navigates between views, the document
// `<title>` is updated by React 19's `<title>` hoisting from inside the
// view body, but the change is silent for SR users — they have no
// browser address bar to read out, and the heading-of-the-day they hit
// next depends on which content has rendered. Announce the same string
// `formatPageTitle(...)` produces for the document title through the
// polite live region so SR users hear the page name on each navigation.
// Keys map to the nav labels the sidebar already shows so the spoken
// name and the visual sidebar entry agree.
// ---------------------------------------------------------------------------

const VIEW_TITLE_KEYS: Record<Exclude<View['type'], 'list'>, TranslationKey> = {
  today: 'nav.today',
  someday: 'nav.someday',
  ai_changelog: 'nav.changelog',
  upcoming: 'nav.upcoming',
  all_tasks: 'nav.allTasks',
  memory: 'nav.memory',
  settings: 'nav.settings',
  review: 'nav.review',
  daily_review: 'nav.daily_review',
  calendar: 'nav.calendar',
  eisenhower: 'nav.eisenhower',
  kanban: 'nav.kanban',
  dependencies: 'nav.dependencies',
  habits: 'nav.habits',
  recurring: 'nav.recurring',
};

// ---------------------------------------------------------------------------
// Main view content
// ---------------------------------------------------------------------------

interface MainViewContentProps {
  view: View;
  overview: Overview | null;
  onSelectTask: (taskId: string | null) => void;
  onNavigate: (view: View) => void;
  /**
   * Opens the QuickCapture overlay. Forwarded to list-based views so
   * their header "+ Add task" buttons route to the same entry point as
   * the ⌘N global shortcut (issue — align add-entry-point
   * placement across all entity-list views). Accepts optional
   * `initialData` so a view can pre-select state it already knows about
   * (e.g. Kanban passes the active list filter through as `list`, per
   * the follow-up).
   */
  onOpenQuickCapture?: ((data?: QuickCaptureInitialData) => void) | undefined;
  isOverviewError?: boolean;
  onRetryOverview?: () => void;
}

export default function MainViewContent({
  view,
  overview,
  onSelectTask,
  onNavigate,
  onOpenQuickCapture,
  isOverviewError = false,
  onRetryOverview,
}: MainViewContentProps) {
  const { t } = useI18n();
  // Memoize a navigation token over the `view` reference to force
  // error-boundary reset when navigating back to the same view (e.g.
  // list A -> today -> list A). Render-time ref mutation is unsafe
  // under React 19 StrictMode + concurrent rendering, so we rely on
  // the parent navigation handler handing back a new `view` object on
  // every navigation (including same-type navigations): the memo
  // recomputes exactly once per commit, producing a stable
  // navigation token even under double-render.
  // `view` is intentionally a dep even though the factory never reads
  // it — we want a fresh Symbol identity on every navigation, which is
  // exactly what including `view` (a new object per navigation) gives
  // us. ESLint flags this as "unnecessary" because the closure body
  // doesn't reference `view`; the navigation-token semantics are the
  // whole point of the memo.
  // eslint-disable-next-line react-hooks/exhaustive-deps -- intentional navigation-token key.
  const nav = useMemo(() => Symbol('nav'), [view]);

  // Zero-arg adapter for views whose "+ Add task" header doesn't pass
  // any initial data (Eisenhower, Dependency Graph). Kanban builds its
  // own adapter inline so it can thread the active list filter as
  // `initialData.list`.
  const openQuickCaptureNoArgs = useCallback(() => {
    onOpenQuickCapture?.();
  }, [onOpenQuickCapture]);

  // announce the document page title to SR users on
  // every view change. React 19 hoists the per-view `<title>` element
  // into `<head>` and removes it on unmount so the document title is
  // always correct, but SR users have no browser address bar reading
  // out the title — they only hear it if it's pushed through the
  // polite live region. We dedupe via a ref so re-renders that don't
  // change the view don't re-announce.
  const lastAnnouncedTitleRef = useRef<string | null>(null);
  useEffect(() => {
    const titleKey = view.type === 'list' ? 'nav.lists' : VIEW_TITLE_KEYS[view.type];
    if (!titleKey) return;
    const next = formatPageTitle(t(titleKey));
    if (lastAnnouncedTitleRef.current === next) return;
    lastAnnouncedTitleRef.current = next;
    announce(next);
  }, [t, view]);

  switch (view.type) {
    case 'today':
      return (
        <ViewBoundary resetKeys={['today', nav]}>
          {isOverviewError && !overview ? (
            <div className="flex flex-col items-center justify-center gap-4 py-24 text-center px-4 sm:px-8">
              <p className="text-text-secondary text-sm">{t('today.loadFailed')}</p>
              <p className="text-text-muted text-xs">{t('today.loadFailedHint')}</p>
              <button
                type="button"
                onClick={() => onRetryOverview?.()}
                className="text-xs px-3 py-1.5 rounded-r-card bg-accent text-on-accent active:scale-[0.97] hover:bg-accent/90 transition-colors focus-ring-strong"
              >
                {t('error.tryAgain')}
              </button>
            </div>
          ) : (
            <TodayView
              overview={overview}
              onNavigate={onNavigate}
              onSelectTask={onSelectTask}
              onAddTask={openQuickCaptureNoArgs}
            />
          )}
        </ViewBoundary>
      );

    case 'list':
      return (
        <ViewBoundary resetKeys={['list', view.listId, nav]}>
          <ListView
            listId={view.listId}
            initialRename={view.rename}
            onSelectTask={onSelectTask}
            onListDeleted={() => {
              onSelectTask(null);
              onNavigate({ type: 'today' });
            }}
          />
        </ViewBoundary>
      );

    case 'someday':
      return (
        <ViewBoundary resetKeys={['someday', nav]}>
          <SomedayView onSelectTask={onSelectTask} onOpenQuickCapture={onOpenQuickCapture} />
        </ViewBoundary>
      );

    case 'ai_changelog':
      // ChangelogView uses useSuspenseQuery; wrap it in a nested
      // Suspense so the in-view data fetch shows a content-shaped
      // skeleton instead of the generic ViewLoadingFallback.
      return (
        <ViewBoundary resetKeys={['ai_changelog', nav]}>
          <Suspense fallback={<ChangelogSkeleton />}>
            <ChangelogView onSelectTask={onSelectTask} onNavigate={onNavigate} />
          </Suspense>
        </ViewBoundary>
      );

    case 'upcoming':
      return (
        <ViewBoundary resetKeys={['upcoming', nav]}>
          <UpcomingView onSelectTask={onSelectTask} onAddTask={onOpenQuickCapture} />
        </ViewBoundary>
      );

    case 'all_tasks':
      return (
        <ViewBoundary resetKeys={['all_tasks', view.initialSearch, nav]}>
          <AllTasksView
            onSelectTask={onSelectTask}
            initialSearch={view.initialSearch}
            onAddTask={onOpenQuickCapture}
          />
        </ViewBoundary>
      );

    case 'memory':
      return (
        <ViewBoundary resetKeys={['memory', nav]}>
          <AIMemoryView onNavigate={onNavigate} />
        </ViewBoundary>
      );

    case 'settings':
      return (
        <ViewBoundary resetKeys={['settings', view.sectionId ?? '', nav]}>
          <SettingsView initialSectionId={view.sectionId} />
        </ViewBoundary>
      );

    case 'review':
      return (
        <ViewBoundary resetKeys={['review', nav]}>
          <WeeklyReviewView
            onSelectTask={onSelectTask}
            onOpenList={(listId) => {
              onSelectTask(null);
              onNavigate({ type: 'list', listId });
            }}
          />
        </ViewBoundary>
      );

    case 'daily_review':
      return (
        <ViewBoundary resetKeys={['daily_review', nav]}>
          <DailyReviewView onNavigate={onNavigate} />
        </ViewBoundary>
      );

    case 'calendar':
      return (
        <ViewBoundary resetKeys={['calendar', nav]}>
          <CalendarView />
        </ViewBoundary>
      );

    case 'eisenhower':
      return (
        <ViewBoundary resetKeys={['eisenhower', nav]}>
          <EisenhowerView onSelectTask={onSelectTask} onAddTask={openQuickCaptureNoArgs} />
        </ViewBoundary>
      );

    case 'kanban':
      return (
        <ViewBoundary resetKeys={['kanban', nav]}>
          <KanbanView
            onSelectTask={onSelectTask}
            onAddTask={(listId) => {
              // Pre-fill the Kanban list-filter as the QuickCapture
              // list so "+ Add task" on a filtered board lands the new
              // task in the list the user is looking at.
              onOpenQuickCapture?.(listId ? { list: listId } : undefined);
            }}
          />
        </ViewBoundary>
      );

    case 'dependencies':
      return (
        <ViewBoundary resetKeys={['dependencies', nav]}>
          <DependencyGraphView onSelectTask={onSelectTask} onAddTask={openQuickCaptureNoArgs} />
        </ViewBoundary>
      );

    case 'habits':
      return (
        <ViewBoundary resetKeys={['habits', nav]}>
          <HabitsView onNavigate={onNavigate} />
        </ViewBoundary>
      );

    case 'recurring':
      return (
        <ViewBoundary resetKeys={['recurring', nav]}>
          <RecurringTasksView onSelectTask={onSelectTask} onOpenQuickCapture={onOpenQuickCapture} />
        </ViewBoundary>
      );
  }

  // TypeScript exhaustiveness check — this should be unreachable if the switch
  // covers all View['type'] variants. A compile error here means a new view type
  // was added without handling it above.
  const _exhaustive: never = view;
  return _exhaustive;
}
