/**
 * DailyReviewSkeleton — content-shaped placeholder for the
 * "Past entries" sub-section of the Daily Review view while its query
 * is loading. The upper sections (Day Summary, Mood, Reflection,
 * Save/Streak) are rendered directly with no loading state, so this
 * skeleton only needs to mirror the list of past review cards.
 */

import { useI18n } from '@/lib/i18n';
import { Bar } from '../ui/SkeletonShimmer';

export function DailyReviewSkeleton() {
  const { t } = useI18n();
  return (
    <section
      className="space-y-4 animate-pulse"
      role="status"
      aria-label={t('common.loading')}
    >
      {/* Section heading ("Past entries · N") */}
      <div className="flex items-center gap-2">
        <Bar className="h-4 w-4 rounded-r-control" />
        <Bar className="h-3 w-24" />
        <Bar className="h-3 w-6" />
      </div>

      {/* Review cards */}
      <div className="space-y-4">
        <Bar className="h-24 w-full rounded-r-card" />
        <Bar className="h-24 w-full rounded-r-card" />
        <Bar className="h-24 w-5/6 rounded-r-card" />
      </div>
    </section>
  );
}
