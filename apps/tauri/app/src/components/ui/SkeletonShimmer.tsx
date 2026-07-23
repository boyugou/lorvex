/**
 * Skeleton shimmer placeholders for loading states.
 *
 * Each exported component mimics the layout of its corresponding view so the
 * user sees a content-shaped pulse instead of a plain "Loading..." label.
 */

import { useI18n } from '@/lib/i18n';

// ---------------------------------------------------------------------------
// Primitive bar — reusable across all skeletons
// ---------------------------------------------------------------------------

export function Bar({ className }: { className: string }) {
  // `skeleton-shimmer` paints a left-to-right gradient sweep;
  // it replaces `bg-surface-2` for the resting fill and gates the
  // sweep animation behind `prefers-reduced-motion: no-preference`,
  // so reduced-motion users see a static surface-2 placeholder.
  return <div className={`rounded-r-control skeleton-shimmer ${className}`} />;
}

// ---------------------------------------------------------------------------
// TodayViewSkeleton — greeting + task cards + stats
// ---------------------------------------------------------------------------

export function TodayViewSkeleton() {
  const { t } = useI18n();
  // Mirror the real TodayHeader shape so the layout doesn't shift when the
  // header replaces the skeleton on first paint:
  //   - greeting eyebrow (uppercase tracking-widest, ~text-2xs)
  //   - large day-of-week h2 (~text-2xl)
  //   - row of pills (overdue / today counts)
  //   - day-progress bar + counter
  //   - task card list
  return (
    <div className="flex flex-col gap-6 animate-pulse" role="status" aria-label={t('common.loading')}>
      <header className="px-4 sm:px-8 pt-1.5 pb-5">
        <div className="flex items-baseline justify-between">
          <div className="space-y-1.5">
            {/* Greeting eyebrow */}
            <Bar className="h-3 w-24" />
            {/* Day-of-week heading */}
            <Bar className="h-7 w-56" />
          </div>
          {/* Right-side action buttons (copy plan / select) */}
          <Bar className="h-7 w-20 rounded-r-control" />
        </div>
        {/* Pills row (overdue/today counts) */}
        <div className="flex items-center gap-2 mt-3">
          <Bar className="h-5 w-20 rounded-full" />
          <Bar className="h-5 w-24 rounded-full" />
        </div>
        {/* Day-progress bar + tabular counter */}
        <div className="mt-3.5 flex items-center gap-3">
          <Bar className="h-1.5 flex-1 rounded-full" />
          <Bar className="h-3 w-10" />
        </div>
      </header>

      {/* Task card placeholders */}
      <div className="space-y-3 px-4 sm:px-8">
        <Bar className="h-16 w-full rounded-r-card" />
        <Bar className="h-16 w-full rounded-r-card" />
        <Bar className="h-16 w-full rounded-r-card" />
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// ListViewSkeleton — title bar + rows
// ---------------------------------------------------------------------------

export function ListViewSkeleton() {
  const { t } = useI18n();
  return (
    <div className="space-y-4 px-4 sm:px-8 py-6 animate-pulse" role="status" aria-label={t('common.loading')}>
      {/* List title */}
      <Bar className="h-5 w-36" />

      {/* Task rows */}
      <div className="space-y-2">
        <Bar className="h-11 w-full rounded-r-control" />
        <Bar className="h-11 w-full rounded-r-control" />
        <Bar className="h-11 w-full rounded-r-control" />
        <Bar className="h-11 w-full rounded-r-control" />
        <Bar className="h-11 w-3/4 rounded-r-control" />
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// TaskDetailSkeleton — title + metadata grid + notes
// ---------------------------------------------------------------------------

export function TaskDetailSkeleton() {
  const { t } = useI18n();
  return (
    <div className="space-y-5 px-6 py-4 animate-pulse" role="status" aria-label={t('common.loading')}>
      {/* Title */}
      <Bar className="h-6 w-3/4" />

      {/* Metadata flex stack — TaskDetail's metadata renders as a vertical
         stack of key/value rows, not a 2-column grid. The previous grid
         created an off-by-one mismatch on first paint when the real view
         landed (rows reflowed into a single column), causing visible jank. */}
      <div className="flex flex-col gap-2.5">
        <Bar className="h-4 w-40" />
        <Bar className="h-4 w-32" />
        <Bar className="h-4 w-48" />
        <Bar className="h-4 w-36" />
      </div>

      {/* Notes area */}
      <div className="space-y-2 pt-2">
        <Bar className="h-4 w-full" />
        <Bar className="h-4 w-5/6" />
        <Bar className="h-4 w-2/3" />
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// TaskListSkeleton — generic card-list skeleton used by AllTasks, Someday,
// Upcoming, Eisenhower, Kanban, DependencyGraph, etc.
// ---------------------------------------------------------------------------

export function TaskListSkeleton() {
  const { t } = useI18n();
  return (
    <div className="space-y-4 py-6 animate-pulse" role="status" aria-label={t('common.loading')}>
      <Bar className="h-4 w-28" />
      <div className="space-y-2">
        <Bar className="h-12 w-full rounded-r-card" />
        <Bar className="h-12 w-full rounded-r-card" />
        <Bar className="h-12 w-full rounded-r-card" />
        <Bar className="h-12 w-5/6 rounded-r-card" />
      </div>
    </div>
  );
}

