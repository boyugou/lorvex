/**
 * WeeklyReviewSkeleton — content-shaped placeholder for the Weekly
 * Review page while the review summary query is loading.
 *
 * The real page opens with a 4-up stat grid, followed by a stack of
 * collapsible review sections. The skeleton mirrors that layout so the
 * page does not visibly reflow as the data lands.
 */

import { useI18n } from '@/lib/i18n';
import { Bar } from '../ui/SkeletonShimmer';

export function WeeklyReviewSkeleton() {
  const { t } = useI18n();
  return (
    <div
      className="space-y-10 py-4 animate-pulse"
      role="status"
      aria-label={t('common.loading')}
    >
      {/* Week at a Glance — 4 stat cards */}
      <section>
        <div className="grid grid-cols-2 xl:grid-cols-4 gap-3">
          <Bar className="h-20 w-full rounded-r-card" />
          <Bar className="h-20 w-full rounded-r-card" />
          <Bar className="h-20 w-full rounded-r-card" />
          <Bar className="h-20 w-full rounded-r-card" />
        </div>
      </section>

      {/* Accomplishments section */}
      <section className="space-y-3">
        <Bar className="h-5 w-40" />
        <Bar className="h-4 w-64" />
        <div className="space-y-2 pt-2">
          <Bar className="h-11 w-full rounded-r-control" />
          <Bar className="h-11 w-full rounded-r-control" />
          <Bar className="h-11 w-4/5 rounded-r-control" />
        </div>
      </section>

      {/* Attention Needed section */}
      <section className="space-y-3">
        <Bar className="h-5 w-48" />
        <Bar className="h-4 w-56" />
        <div className="space-y-2 pt-2">
          <Bar className="h-11 w-full rounded-r-control" />
          <Bar className="h-11 w-3/4 rounded-r-control" />
        </div>
      </section>
    </div>
  );
}
