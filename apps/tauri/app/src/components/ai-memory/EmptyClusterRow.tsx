import type { useI18n } from '@/lib/i18n';
import type { MemoryCluster } from './helpers';
import { CLUSTER_EMPTY_CTA_KEY, CLUSTER_LABEL_KEY } from './clusterLabels';

/**
 * Faded "ghost" cluster row rendered when the user has no entries in
 * a cluster (preferences / people / projects / facts). Surfaces the
 * cluster taxonomy itself + a per-cluster "Teach me about a person /
 * preference / project / fact" CTA so a fresh user sees what kinds
 * of things the assistant can be taught about. Clicking the CTA
 * routes to the same inline "+ Add memory" form the header offers.
 */
export function EmptyClusterRow({
  cluster,
  t,
  onOpenAddForm,
}: {
  cluster: MemoryCluster;
  t: ReturnType<typeof useI18n>['t'];
  onOpenAddForm: () => void;
}) {
  return (
    <section aria-label={t(CLUSTER_LABEL_KEY[cluster])} className="opacity-60 hover:opacity-100 transition-opacity">
      <h3 className="-mx-1 mb-2 px-1 py-1 text-text-muted text-2xs font-semibold tracking-widest uppercase">
        {t(CLUSTER_LABEL_KEY[cluster])}
      </h3>
      <div className="rounded-r-card border border-dashed border-surface-3 bg-surface-2/30 px-4 py-3 flex items-center justify-between gap-3">
        <p className="text-xs text-text-muted leading-relaxed">
          {t('memory.cluster.emptyHint')}
        </p>
        <button
          type="button"
          onClick={onOpenAddForm}
          className="shrink-0 text-2xs font-medium text-accent hover:text-accent/80 hover:bg-accent/10 px-2 py-1 rounded-r-control transition-colors focus-ring-soft"
        >
          + {t(CLUSTER_EMPTY_CTA_KEY[cluster])}
        </button>
      </div>
    </section>
  );
}
