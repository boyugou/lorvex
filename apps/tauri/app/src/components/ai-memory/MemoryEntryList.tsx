import type { useI18n } from '@/lib/i18n';
import type { AIMemoryEntry } from '@/lib/ipc/memory';
import { useListJkNavigation } from '@/lib/useListJkNavigation';
import { MemoryEntryCard } from './MemoryEntryCard';
import { ClusterSection } from './ClusterSection';
import { EmptyClusterRow } from './EmptyClusterRow';
import { MEMORY_CLUSTER_ORDER, type MemoryCluster } from './helpers';
import { groupEntriesByCluster } from './clusterLabels';

/**
 * Memory entry list. Owns the j/k navigation (sized to the visible
 * memory entries — filtered upstream by the parent's search state)
 * and the cluster decomposition. Entries render grouped by inferred
 * editorial cluster (preferences/people/projects/facts) with a
 * sticky sub-header per cluster. j/k navigation still walks a single
 * flat ordering, so keyboard users don't have to think about
 * clusters.
 *
 * Hoisting the j/k hook into the parent would force it to recompute
 * the filter twice; this keeps the hook co-located with the list.
 */
export function MemoryEntryList({
  entries,
  locale,
  timezone,
  t,
  onMutate,
  onOpenAddForm,
}: {
  entries: AIMemoryEntry[];
  locale: string;
  timezone: string;
  t: ReturnType<typeof useI18n>['t'];
  onMutate: () => void;
  /**
   * Callback that opens the inline "+ Add memory" form. Wired into
   * the faded empty-cluster rows so a CTA there lands the user on
   * the same form the header button uses; the form itself is the
   * single human-owned creation surface for memory rows. When
   * invoked from an empty-cluster row, the cluster argument lets the
   * parent pre-fill the form's key with the matching `<cluster>.`
   * namespace so the resulting entry lands back in the same cluster
   * lane.
   */
  onOpenAddForm: (cluster?: MemoryCluster) => void;
}) {
  // Flat list drives j/k navigation; visual grouping below uses the
  // same entries so the index↔ref mapping stays in sync.
  const jk = useListJkNavigation(entries.length);
  const groups = groupEntriesByCluster(entries);

  // Clusters that exist in the taxonomy but the user hasn't filled
  // in yet — rendered as a faded ghost row so the user discovers the
  // taxonomy ("yes you can teach the assistant about People") even
  // before any entry exists in that cluster. Hidden when search is
  // active (search-by-content is the user's stated intent; cluster
  // discovery would distract).
  const presentClusters = new Set(groups.map((g) => g.cluster));
  const emptyClusters: MemoryCluster[] = MEMORY_CLUSTER_ORDER.filter((c) => !presentClusters.has(c));

  // Single entry: skip the cluster header chrome — it would only add
  // visual noise.
  if (entries.length <= 1 || groups.length <= 1) {
    return (
      <div className="space-y-3">
        {entries.map((entry, index) => (
          <div
            key={entry.key}
            ref={jk.register(index)}
            tabIndex={-1}
            className="focus-ring-soft rounded-r-card"
          >
            <MemoryEntryCard
              entry={entry}
              locale={locale}
              timezone={timezone}
              t={t}
              onMutate={onMutate}
            />
          </div>
        ))}
      </div>
    );
  }

  // Walk groups in editorial order, but assign a globally-monotonic
  // index per entry so the j/k hook's flat ref array stays aligned
  // with `entries.length` (which is what `useListJkNavigation` was
  // sized for).
  let flatIndex = 0;
  return (
    <div className="space-y-6">
      {emptyClusters.map((cluster) => (
        <EmptyClusterRow
          key={`empty-${cluster}`}
          cluster={cluster}
          t={t}
          onOpenAddForm={() => onOpenAddForm(cluster)}
        />
      ))}
      {groups.map(({ cluster, entries: clusterEntries }) => {
        const startIndex = flatIndex;
        flatIndex += clusterEntries.length;
        return (
          <ClusterSection
            key={cluster}
            cluster={cluster}
            entries={clusterEntries}
            startIndex={startIndex}
            register={jk.register}
            locale={locale}
            timezone={timezone}
            t={t}
            onMutate={onMutate}
          />
        );
      })}
    </div>
  );
}
