/**
 * KanbanViewSkeleton — column-shaped placeholder for the Kanban board
 * while the task query is loading.
 *
 * The real board renders a horizontal flex of three columns
 * (open / someday / completed; see `./columns.ts`). The skeleton
 * mirrors the column shell — rounded border, header row, body of card
 * placeholders — so the handoff to real content doesn't reflow the
 * page. The shimmer is gated behind `motion-safe:` so users with
 * `prefers-reduced-motion: reduce` see a static silhouette.
 */

import { useI18n } from '@/lib/i18n';
import { Bar } from '../ui/SkeletonShimmer';
import { COLUMN_ORDER } from './columns';

// Per-column placeholder counts — chosen to roughly match the visual
// weight of a real board (more cards in `open`, fewer in `someday`,
// a couple in `completed`). Adjusting per column instead of using a
// uniform count gives the skeleton a less mechanical rhythm.
const COLUMN_PLACEHOLDER_COUNT: Record<(typeof COLUMN_ORDER)[number], number> = {
  open: 4,
  someday: 2,
  completed: 3,
};

export function KanbanViewSkeleton() {
  const { t } = useI18n();
  return (
    <div
      className="flex gap-4 h-full min-w-0 motion-safe:animate-pulse"
      role="status"
      aria-label={t('common.loading')}
    >
      {COLUMN_ORDER.map((key) => (
        <section
          key={key}
          className="rounded-r-card border border-surface-3 bg-surface-2/40 p-3 min-w-[160px] md:min-w-[220px] min-h-[300px] flex-1 flex flex-col"
        >
          {/* Column header — title + count chip */}
          <div className="mb-3 shrink-0 flex items-center justify-between gap-2">
            <Bar className="h-4 w-20" />
            <Bar className="h-3 w-6" />
          </div>

          {/* Card placeholders */}
          <div className="flex-1 space-y-1.5">
            {Array.from({ length: COLUMN_PLACEHOLDER_COUNT[key] }).map((_, i) => (
              <Bar key={i} className="h-12 w-full rounded-r-card" />
            ))}
          </div>
        </section>
      ))}
    </div>
  );
}
