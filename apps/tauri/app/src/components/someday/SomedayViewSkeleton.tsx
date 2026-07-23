/**
 * SomedayViewSkeleton — list-row placeholder for the Someday view
 * while the task query is loading.
 *
 * The real view renders task cards stacked vertically inside the
 * scroll container (no per-section grouping when the list is empty).
 * The skeleton just mirrors the card rhythm — full-width rounded
 * silhouettes with a tapering last row — so users see content-shaped
 * weight rather than a centered spinner. Shimmer is `motion-safe:`
 * gated for `prefers-reduced-motion`.
 */

import { useI18n } from '@/lib/i18n';
import { Bar } from '../ui/SkeletonShimmer';

export function SomedayViewSkeleton() {
  const { t } = useI18n();
  return (
    <div
      className="space-y-1.5 py-2 motion-safe:animate-pulse"
      role="status"
      aria-label={t('common.loading')}
    >
      <Bar className="h-12 w-full rounded-r-card" />
      <Bar className="h-12 w-full rounded-r-card" />
      <Bar className="h-12 w-11/12 rounded-r-card" />
      <Bar className="h-12 w-full rounded-r-card" />
      <Bar className="h-12 w-5/6 rounded-r-card" />
      <Bar className="h-12 w-full rounded-r-card" />
      <Bar className="h-12 w-2/3 rounded-r-card" />
    </div>
  );
}
