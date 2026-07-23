/**
 * HabitsViewSkeleton — content-shaped placeholder for the Habits page
 * while the habits-with-stats query is loading.
 *
 * The real page renders a header plus a responsive grid of habit cards
 * (1 column on narrow viewports, 2 columns at xl). The skeleton
 * renders the same header + grid shape so the handoff to real content
 * is imperceptible.
 */

import { useI18n } from '@/lib/i18n';
import { Bar } from '../ui/SkeletonShimmer';

export function HabitsViewSkeleton() {
  const { t } = useI18n();
  return (
    <div
      className="h-full overflow-y-auto"
      role="status"
      aria-label={t('common.loading')}
    >
      <div className="px-4 sm:px-8 pt-1.5 pb-5 animate-pulse">
        {/* Page header */}
        <div className="mb-8 space-y-2">
          <Bar className="h-7 w-40" />
          <Bar className="h-3 w-72" />
        </div>

        {/* Habit cards grid */}
        <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
          <Bar className="h-40 w-full rounded-r-card" />
          <Bar className="h-40 w-full rounded-r-card" />
          <Bar className="h-40 w-full rounded-r-card" />
          <Bar className="h-40 w-full rounded-r-card" />
        </div>
      </div>
    </div>
  );
}
