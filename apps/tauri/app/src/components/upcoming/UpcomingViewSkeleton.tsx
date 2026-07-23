/**
 * UpcomingViewSkeleton — content-shaped placeholder for the Upcoming
 * view while the tasks + events queries are loading.
 *
 * Upcoming groups rows by date; each group has a day-header line
 * followed by a handful of rows. This skeleton mirrors that rhythm
 * across a few visible days so the transition to real content is
 * visually seamless.
 */

import { useI18n } from '@/lib/i18n';
import { Bar } from '../ui/SkeletonShimmer';

export function UpcomingViewSkeleton() {
  const { t } = useI18n();
  return (
    <div
      className="space-y-6 py-4 animate-pulse"
      role="status"
      aria-label={t('common.loading')}
    >
      {/* Day 1 */}
      <div className="space-y-2">
        <Bar className="h-4 w-28" />
        <Bar className="h-12 w-full rounded-r-card" />
        <Bar className="h-12 w-full rounded-r-card" />
        <Bar className="h-12 w-4/5 rounded-r-card" />
      </div>

      {/* Day 2 */}
      <div className="space-y-2">
        <Bar className="h-4 w-32" />
        <Bar className="h-12 w-full rounded-r-card" />
        <Bar className="h-12 w-11/12 rounded-r-card" />
      </div>

      {/* Day 3 */}
      <div className="space-y-2">
        <Bar className="h-4 w-24" />
        <Bar className="h-12 w-full rounded-r-card" />
        <Bar className="h-12 w-full rounded-r-card" />
        <Bar className="h-12 w-2/3 rounded-r-card" />
      </div>
    </div>
  );
}
