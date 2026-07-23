/**
 * AIMemorySkeleton — content-shaped placeholder for the AI Memory
 * page while the memory entries query is loading.
 *
 * The page layout is a "Notes for AI" section on top, then a list of
 * memory entry cards. The skeleton mirrors that two-band rhythm.
 */

import { useI18n } from '@/lib/i18n';
import { Bar } from '../ui/SkeletonShimmer';

export function AIMemorySkeleton() {
  const { t } = useI18n();
  return (
    <div
      className="space-y-6 py-4 animate-pulse"
      role="status"
      aria-label={t('common.loading')}
    >
      {/* Notes for AI section */}
      <section className="space-y-3">
        <Bar className="h-5 w-36" />
        <Bar className="h-24 w-full rounded-r-card" />
      </section>

      {/* Memory entries list */}
      <section className="space-y-3">
        <Bar className="h-5 w-44" />
        <div className="space-y-2">
          <Bar className="h-16 w-full rounded-r-card" />
          <Bar className="h-16 w-full rounded-r-card" />
          <Bar className="h-16 w-full rounded-r-card" />
          <Bar className="h-16 w-5/6 rounded-r-card" />
        </div>
      </section>
    </div>
  );
}
