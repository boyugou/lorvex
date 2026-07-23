/**
 * EisenhowerViewSkeleton — quadrant-shaped placeholder for the
 * Eisenhower matrix while the task query is loading.
 *
 * The real matrix renders a 1-column / 2-column responsive grid of
 * four quadrant cards. Each quadrant has a title + hint header and
 * a body of task rows. The skeleton mirrors that geometry exactly,
 * so the layout doesn't shift when real data arrives. Shimmer is
 * gated behind `motion-safe:` to honor `prefers-reduced-motion`.
 */

import { useI18n } from '@/lib/i18n';
import { Bar } from '../ui/SkeletonShimmer';
import { QUADRANT_KEYS } from './quadrants';

export function EisenhowerViewSkeleton() {
  const { t } = useI18n();
  return (
    <div
      className="grid grid-cols-1 lg:grid-cols-2 lg:auto-rows-fr gap-4 motion-safe:animate-pulse"
      role="status"
      aria-label={t('common.loading')}
    >
      {QUADRANT_KEYS.map((key) => (
        <section
          key={key}
          className="rounded-r-card border border-surface-3 bg-surface-2/40 p-3 min-h-[min(280px,30vh)] flex flex-col"
        >
          {/* Quadrant header — title + count chip + hint line */}
          <div className="mb-3">
            <div className="flex items-center justify-between gap-2">
              <Bar className="h-4 w-32" />
              <Bar className="h-3 w-6" />
            </div>
            <Bar className="h-3 w-44 mt-1.5" />
          </div>

          {/* Task row placeholders — 4 per quadrant */}
          <div className="flex-1 space-y-1.5">
            <Bar className="h-12 w-full rounded-r-card" />
            <Bar className="h-12 w-full rounded-r-card" />
            <Bar className="h-12 w-11/12 rounded-r-card" />
            <Bar className="h-12 w-3/4 rounded-r-card" />
          </div>
        </section>
      ))}
    </div>
  );
}
