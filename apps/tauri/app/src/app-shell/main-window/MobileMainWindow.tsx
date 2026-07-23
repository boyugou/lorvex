import { Fragment, useCallback, useRef, useState, type ReactNode } from 'react';

import ErrorBoundary from '@/components/ErrorBoundary';
import MainViewContent from '@/components/MainViewContent';
import TaskDetail from '@/components/TaskDetail';
import { ModalShell } from '@/components/ui/overlay';
import { ToggleChip } from '@/components/ui/ToggleChip';
import { formatTodayTaskCountLabel } from '@/lib/dates/i18nCountPhrases';
import { useI18n, type TranslationKey } from '@/lib/i18n';
import type { View } from '@/lib/types';
import { useVisualViewportInset } from '@/lib/useVisualViewport';

import type { MainWindowController } from './types';

const MOBILE_TAB_BADGE_MAX = 99;

interface MobileTabBadge {
  accessibilityLabel: string;
  count: number;
  visualLabel: string;
}

function MobileTabButton({ icon, label, active, badge, onClick, ...ariaProps }: {
  icon: ReactNode;
  label: string;
  active: boolean;
  badge?: MobileTabBadge | null | undefined;
  onClick: () => void;
  'aria-expanded'?: boolean;
  'aria-haspopup'?: 'dialog' | 'menu' | 'listbox' | 'tree' | 'grid' | 'true' | 'false';
}) {
  const hasBadge = badge != null && badge.count > 0;
  return (
    <button
      type="button"
      onClick={onClick}
      className={`relative flex flex-col items-center justify-center gap-0.5 transition-colors ${
        active ? 'text-accent' : 'text-text-muted'
      }`}
      aria-current={active ? 'page' : undefined}
      aria-label={hasBadge ? `${label}, ${badge.accessibilityLabel}` : undefined}
      {...ariaProps}
    >
      <span className="relative">
        {icon}
        {hasBadge && (
          <span
            className="absolute -top-1 -end-2.5 min-w-[16px] h-4 rounded-full bg-danger text-[9px] text-on-accent font-medium flex items-center justify-center px-1"
            aria-hidden="true"
          >
            {badge.visualLabel}
          </span>
        )}
      </span>
      <span className="text-3xs leading-none">{label}</span>
    </button>
  );
}

interface MobileMainWindowProps {
  controller: MainWindowController;
}

export function MobileMainWindow({ controller }: MobileMainWindowProps) {
  const { locale, t, formatNumber } = useI18n();
  // expose soft-keyboard inset as `--kb-inset` so the
  // fixed bottom tab bar and any bottom-anchored modal footers can
  // shift above the keyboard on Android.
  useVisualViewportInset();
  const {
    handleSidebarNavigate,
    isOverviewError,
    lists,
    mobileTitle,
    navigateToView,
    onRetryOverview,
    onSelectTask,
    openMobileLists,
    openQuickCapture,
    overview,
    selectMobileList,
    selectedTaskId,
    setSelectedTaskId,
    view,
  } = controller;

  const [showMoreMenu, setShowMoreMenu] = useState(false);
  const taskDetailFlushDraftsRef = useRef<(() => Promise<boolean>) | null>(null);
  const closeTaskDetail = useCallback(() => {
    const flush = taskDetailFlushDraftsRef.current;
    if (!flush) {
      setSelectedTaskId(null);
      return;
    }
    void flush().then((ok) => {
      if (ok) setSelectedTaskId(null);
    });
  }, [setSelectedTaskId]);
  // type labelKey as TranslationKey so a rename in en.ts
  // surfaces as a compile error instead of the `as Parameters<typeof t>[0]`
  // cast at render time silently papering over the drift.
  const moreViews: Array<{ type: View['type']; icon: string; labelKey: TranslationKey; dividerBefore?: boolean }> = [
    // Primary — frequently used
    { type: 'someday', icon: '💭', labelKey: 'nav.someday' },
    { type: 'calendar', icon: '📅', labelKey: 'nav.calendar' },
    { type: 'daily_review', icon: '📓', labelKey: 'nav.daily_review' },
    { type: 'review', icon: '📊', labelKey: 'nav.review' },
    // Planning & workflows
    { type: 'habits', icon: '🔥', labelKey: 'nav.habits', dividerBefore: true },
    { type: 'eisenhower', icon: '⊞', labelKey: 'nav.eisenhower' },
    { type: 'kanban', icon: '▦', labelKey: 'nav.kanban' },
    { type: 'dependencies', icon: '🔗', labelKey: 'nav.dependencies' },
    { type: 'recurring', icon: '🔁', labelKey: 'nav.recurring' },
    // Secondary — analysis & AI
    { type: 'ai_changelog', icon: '⚡', labelKey: 'nav.changelog', dividerBefore: true },
    { type: 'memory', icon: '✦', labelKey: 'nav.memory' },
    { type: 'all_tasks', icon: '📋', labelKey: 'nav.allTasks' },
    { type: 'settings', icon: '⚙', labelKey: 'nav.settings' },
  ];
  const isMoreViewActive = moreViews.some((v) => v.type === view.type);
  const todayPoolCount = overview?.stats?.today_pool_count ?? 0;
  const todayTabBadge: MobileTabBadge | null = todayPoolCount > 0
    ? {
        accessibilityLabel: formatTodayTaskCountLabel(locale, todayPoolCount, t),
        count: todayPoolCount,
        visualLabel: `${formatNumber(Math.min(todayPoolCount, MOBILE_TAB_BADGE_MAX))}${todayPoolCount > MOBILE_TAB_BADGE_MAX ? '+' : ''}`,
      }
    : null;

  return (
    <>
      {/* align with the desktop shell — render a single
          screen-reader-only `<h1>Lorvex</h1>` at the app root so the
          heading hierarchy stays consistent across runtimes. The
          mobile header's visible per-view title is rendered as a
          `<div role="heading" aria-level={2}>` so views can still
          start at h2 (matching desktop) without skipping a level. */}
      <h1 className="sr-only">Lorvex</h1>
      <header
        className="shrink-0 border-b border-surface-3 bg-surface-1 py-2 pt-[max(0.5rem,env(safe-area-inset-top))]"
        style={{
          paddingInlineStart: 'max(0.75rem, env(safe-area-inset-left, 0px))',
          paddingInlineEnd: 'max(0.75rem, env(safe-area-inset-right, 0px))',
        }}
      >
        <div className="flex items-center justify-between gap-3">
          <div role="heading" aria-level={2} className="truncate text-sm font-semibold text-text-primary">{mobileTitle}</div>
          <div className="flex items-center gap-1.5">
            <button
              type="button"
              onClick={() => handleSidebarNavigate({ type: 'all_tasks' })}
              className="flex h-11 w-11 items-center justify-center rounded-r-card text-text-muted transition-colors active:bg-surface-2"
              title={t('allTasks.search')}
              aria-label={t('allTasks.search')}
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round">
                <circle cx="11" cy="11" r="7" />
                <path d="M21 21l-4.35-4.35" />
              </svg>
            </button>
            <button
              type="button"
              onClick={() => openQuickCapture()}
              className="flex h-11 w-11 items-center justify-center rounded-r-card bg-accent/20 text-xl leading-none text-accent transition-colors active:bg-accent/30"
              title={t('capture.addTask')}
              aria-label={t('capture.addTask')}
            >
              +
            </button>
          </div>
        </div>
        {view.type === 'list' && lists.length > 1 && (
          <div className="mt-2 flex gap-2 overflow-x-auto pb-1">
            {lists.map((list) => {
              const isSelected = view.type === 'list' && view.listId === list.id;
              return (
                <ToggleChip
                  key={list.id}
                  size="sm"
                  onClick={() => {
                    selectMobileList(list.id);
                  }}
                  selected={isSelected}
                  // Mobile filter row carries an explicit border on
                  // both states (idle: surface-3 bordered chip on
                  // surface-2 fill; selected: accent border + canonical
                  // /20 fill). ToggleChip's default treatment is
                  // border-less, so override on both rails.
                  selectedClassName="border border-accent/30 bg-accent/20 text-accent"
                  inactiveClassName="border border-surface-3 bg-surface-2 text-text-secondary"
                  className="!rounded-full px-2.5 whitespace-nowrap"
                  aria-pressed={isSelected}
                >
                  {list.icon ? `${list.icon} ` : ''}
                  {list.name}
                </ToggleChip>
              );
            })}
          </div>
        )}
      </header>

      <main id="main-content" className="flex-1 overflow-hidden" style={{ paddingBottom: 'calc(3.5rem + env(safe-area-inset-bottom, 0px))' }}>
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

      {selectedTaskId !== null && (
        <ModalShell
          open
          onClose={closeTaskDetail}
          backdropDismiss={false}
          ariaLabel={t('task.title')}
          align="items-stretch justify-stretch"
          backdropClassName=""
          panelClassName="w-full h-full min-h-0 bg-surface-1 flex flex-col animate-[slide-in-up_0.2s_ease-out]"
        >
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
              key={selectedTaskId}
              taskId={selectedTaskId}
              onClose={closeTaskDetail}
              onSelectTask={setSelectedTaskId}
              flushDraftsRef={taskDetailFlushDraftsRef}
              isMobile
            />
          </ErrorBoundary>
        </ModalShell>
      )}

      <nav
        // bottom tab nav is sticky chrome — wire it to
        // the canonical `--z-sticky` token instead of the bare `z-30`
        // magic number so it tracks the global stacking scheme
        // alongside KeyboardHintBar et al.
        className="fixed start-0 end-0 z-[var(--z-sticky)] border-t border-surface-3 bg-surface-1/95 backdrop-blur-md pb-[env(safe-area-inset-bottom)]"
        style={{ bottom: 'var(--kb-inset, 0px)' }}
        aria-label={t('nav.primary')}
      >
        <div
          className="grid h-14 grid-cols-4"
          style={{
            paddingInlineStart: 'env(safe-area-inset-left, 0px)',
            paddingInlineEnd: 'env(safe-area-inset-right, 0px)',
          }}
        >
          <MobileTabButton
            icon={<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"><circle cx="12" cy="12" r="5"/><path d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"/></svg>}
            label={t('nav.today')}
            active={view.type === 'today'}
            badge={todayTabBadge}
            onClick={() => handleSidebarNavigate({ type: 'today' })}
          />
          <MobileTabButton
            icon={<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"><rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/></svg>}
            label={t('nav.upcoming')}
            active={view.type === 'upcoming'}
            onClick={() => handleSidebarNavigate({ type: 'upcoming' })}
          />
          <MobileTabButton
            icon={<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"><path d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2"/><rect x="9" y="3" width="6" height="4" rx="1"/><path d="M9 14l2 2 4-4"/></svg>}
            label={t('nav.lists')}
            active={view.type === 'list'}
            onClick={openMobileLists}
          />
          <MobileTabButton
            icon={<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"><circle cx="12" cy="5" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="12" cy="19" r="1"/></svg>}
            label={t('common.more')}
            active={isMoreViewActive}
            onClick={() => setShowMoreMenu(true)}
            aria-expanded={showMoreMenu}
            aria-haspopup="dialog"
          />
        </div>
      </nav>

      {showMoreMenu && (
        <ModalShell
          open
          onClose={() => setShowMoreMenu(false)}
          // bottom-sheet "More" menu is a modal
          // overlay (focus-trapped, scrim-backed) — wire it to the
          // canonical --z-modal token instead of the bare `z-50`
          // magic number so it tracks the global stacking scheme.
          zIndex="z-[var(--z-modal)]"
          align="items-end justify-center"
          backdropClassName="bg-[var(--color-overlay)] animate-[fade-in_0.12s_ease-out]"
          panelClassName="w-full max-h-[calc(100dvh-1rem)] min-h-0 overflow-hidden bg-surface-1 border-t border-surface-3 rounded-t-[var(--radius-r-panel)] flex flex-col animate-[slide-in-up_0.2s_ease-out]"
          ariaLabel={t('common.more')}
        >
          <div className="shrink-0">
            <div className="w-10 h-1 rounded-full bg-surface-3 mx-auto mt-2 mb-3" aria-hidden="true" />
          </div>
          <div
            className="min-h-0 overflow-y-auto pb-4 grid gap-x-2 gap-y-3"
            style={{
              gridTemplateColumns: 'repeat(auto-fit, minmax(min(5.5rem, 100%), 1fr))',
              paddingBottom: 'max(1rem, env(safe-area-inset-bottom, 0px))',
              paddingInlineStart: 'max(1rem, env(safe-area-inset-left, 0px))',
              paddingInlineEnd: 'max(1rem, env(safe-area-inset-right, 0px))',
            }}
          >
            {moreViews.map((item) => (
              <Fragment key={item.type}>
                {item.dividerBefore && (
                  <div className="col-span-full my-0.5 h-px bg-surface-3" aria-hidden="true" />
                )}
                <button
                  type="button"
                  onClick={() => {
                    setShowMoreMenu(false);
                    handleSidebarNavigate({ type: item.type } as View);
                  }}
                  className={`min-w-0 w-full min-h-20 flex flex-col items-center justify-start gap-1.5 px-1.5 py-3 rounded-r-card text-center transition-colors ${
                    view.type === item.type ? 'bg-accent/15 text-accent' : 'text-text-secondary active:bg-surface-2'
                  }`}
                  aria-current={view.type === item.type ? 'page' : undefined}
                >
                  <span className="shrink-0 text-xl leading-none" aria-hidden="true">{item.icon}</span>
                  <span className="min-w-0 max-w-full text-center text-3xs leading-tight whitespace-normal break-words hyphens-auto">{t(item.labelKey)}</span>
                </button>
              </Fragment>
            ))}
          </div>
        </ModalShell>
      )}
    </>
  );
}
