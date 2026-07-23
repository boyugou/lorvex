/**
 * AllTasksViewSkeleton — content-shaped placeholder for the All Tasks
 * list body while the task query is loading.
 *
 * The page header (title, search, filter pills) is already rendered by
 * the parent view, so this skeleton only fills the scrolling content
 * area: a few section headers interleaved with rows of task cards. The
 * goal is a "shape match" rather than pixel-perfect fidelity — once
 * real data arrives the content slides in without a jarring reflow.
 */

import { useI18n } from '@/lib/i18n';
import { Bar } from '../ui/SkeletonShimmer';

export function AllTasksViewSkeleton() {
  const { t } = useI18n();
  return (
    <div
      className="space-y-6 py-4 animate-pulse"
      role="status"
      aria-label={t('common.loading')}
    >
      {/* Section 1 */}
      <div className="space-y-2">
        <Bar className="h-4 w-24" />
        <Bar className="h-12 w-full rounded-r-card" />
        <Bar className="h-12 w-full rounded-r-card" />
        <Bar className="h-12 w-full rounded-r-card" />
        <Bar className="h-12 w-11/12 rounded-r-card" />
      </div>

      {/* Section 2 */}
      <div className="space-y-2">
        <Bar className="h-4 w-32" />
        <Bar className="h-12 w-full rounded-r-card" />
        <Bar className="h-12 w-full rounded-r-card" />
        <Bar className="h-12 w-5/6 rounded-r-card" />
      </div>

      {/* Section 3 */}
      <div className="space-y-2">
        <Bar className="h-4 w-28" />
        <Bar className="h-12 w-full rounded-r-card" />
        <Bar className="h-12 w-3/4 rounded-r-card" />
      </div>
    </div>
  );
}
