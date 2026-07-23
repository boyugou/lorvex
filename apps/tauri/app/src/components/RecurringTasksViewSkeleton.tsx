/**
 * RecurringTasksViewSkeleton — placeholder for the Recurring Tasks
 * dashboard while the recurring-task query is loading.
 *
 * The real view groups rows by FREQ (Daily / Weekly / Monthly /
 * Yearly / Custom) — each group has a small section header and a
 * stack of task cards with a cadence-badge overlay on the right.
 * The skeleton mirrors that rhythm across two visible groups: a
 * header strip plus rows with both a title-line silhouette and a
 * smaller rule-spec line on the right edge.
 *
 * Shimmer is gated behind `motion-safe:` so users with
 * `prefers-reduced-motion: reduce` see a still silhouette.
 */

import { useI18n } from '../lib/i18n';
import { Bar } from './ui/SkeletonShimmer';

function RecurringRow({ titleWidth }: { titleWidth: string }) {
  return (
    <div className="relative">
      <div className="rounded-r-card border border-card bg-surface-2/40 px-4 py-3 flex items-center gap-3">
        {/* Status checkbox circle */}
        <Bar className="h-4 w-4 rounded-full shrink-0" />
        {/* Title line */}
        <Bar className={`h-4 ${titleWidth}`} />
      </div>
      {/* Cadence badge overlay (top-right of the card) */}
      <div className="pointer-events-none absolute top-2.5 end-4 flex items-center">
        <Bar className="h-4 w-16 rounded-full" />
      </div>
    </div>
  );
}

export function RecurringTasksViewSkeleton() {
  const { t } = useI18n();
  return (
    <div
      className="space-y-6 py-2 motion-safe:animate-pulse"
      role="status"
      aria-label={t('common.loading')}
    >
      {/* Group 1 — e.g. Daily */}
      <section>
        <div className="mb-2.5 flex items-center gap-2 px-2 -ms-2">
          <Bar className="h-3 w-16" />
          <Bar className="h-3 w-5 rounded-r-control" />
        </div>
        <div className="space-y-1.5">
          <RecurringRow titleWidth="w-2/3" />
          <RecurringRow titleWidth="w-1/2" />
          <RecurringRow titleWidth="w-3/5" />
        </div>
      </section>

      {/* Group 2 — e.g. Weekly */}
      <section>
        <div className="mb-2.5 flex items-center gap-2 px-2 -ms-2">
          <Bar className="h-3 w-20" />
          <Bar className="h-3 w-5 rounded-r-control" />
        </div>
        <div className="space-y-1.5">
          <RecurringRow titleWidth="w-3/4" />
          <RecurringRow titleWidth="w-1/2" />
        </div>
      </section>
    </div>
  );
}
