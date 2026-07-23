/**
 * ChangelogSkeleton — content-shaped placeholder for the AI Changelog
 * view while the initial entries query resolves via Suspense.
 *
 * The real page opens with a header, a row of operation-filter chips,
 * then a dense list of small entry rows. This skeleton renders the
 * same rhythm so the Suspense fallback blends into the real view.
 */

import { useI18n } from '@/lib/i18n';
import { Bar } from '../ui/SkeletonShimmer';

export function ChangelogSkeleton() {
  const { t } = useI18n();
  return (
    <div
      className="h-full flex flex-col overflow-hidden"
      role="status"
      aria-label={t('common.loading')}
    >
      <header className="px-4 sm:px-8 pt-1.5 pb-5 shrink-0 animate-pulse">
        {/* Breadcrumb label */}
        <Bar className="h-3 w-20" />
        {/* Title */}
        <Bar className="h-7 w-48 mt-1" />
        {/* Subtitle */}
        <Bar className="h-3 w-80 mt-2" />

        {/* Filter chips */}
        <div className="flex items-center gap-1.5 mt-3 flex-wrap">
          <Bar className="h-5 w-16 rounded-full" />
          <Bar className="h-5 w-20 rounded-full" />
          <Bar className="h-5 w-20 rounded-full" />
          <Bar className="h-5 w-24 rounded-full" />
          <Bar className="h-5 w-16 rounded-full" />
        </div>
      </header>

      <div className="flex-1 overflow-hidden px-4 sm:px-8 pb-8 animate-pulse">
        <div className="space-y-1.5">
          <Bar className="h-7 w-full rounded-r-control" />
          <Bar className="h-7 w-full rounded-r-control" />
          <Bar className="h-7 w-full rounded-r-control" />
          <Bar className="h-7 w-11/12 rounded-r-control" />
          <Bar className="h-7 w-full rounded-r-control" />
          <Bar className="h-7 w-5/6 rounded-r-control" />
          <Bar className="h-7 w-full rounded-r-control" />
          <Bar className="h-7 w-3/4 rounded-r-control" />
        </div>
      </div>
    </div>
  );
}
