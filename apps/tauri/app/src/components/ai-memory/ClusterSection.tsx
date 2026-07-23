import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import type { useI18n } from '@/lib/i18n';
import type { AIMemoryEntry } from '@/lib/ipc/memory';
import { MemoryEntryCard } from './MemoryEntryCard';
import type { MemoryCluster } from './helpers';
import { CLUSTER_LABEL_KEY } from './clusterLabels';

/**
 * One cluster's section header + entry list, factored out so each
 * cluster can wire its own IntersectionObserver-driven position cue
 * ("3/8 showing") on the sticky header. When a cluster is taller
 * than the viewport, the sticky header alone shows the static total;
 * pairing it with `currently-visible / total` tells the reader where
 * they are inside that cluster without scrolling back up to find a
 * landmark.
 */
export function ClusterSection({
  cluster,
  entries,
  startIndex,
  register,
  locale,
  timezone,
  t,
  onMutate,
}: {
  cluster: MemoryCluster;
  entries: AIMemoryEntry[];
  startIndex: number;
  register: (index: number) => (node: HTMLElement | null) => void;
  locale: string;
  timezone: string;
  t: ReturnType<typeof useI18n>['t'];
  onMutate: () => void;
}) {
  const [visibleCount, setVisibleCount] = useState(entries.length);
  // First / last currently-intersecting indices feed the 2px scroll-
  // progress underline below the sticky header — the "3/8 showing"
  // count alone reveals coverage but not whether those three rows are
  // at the top, middle, or bottom of the cluster. The underline closes
  // the loop by mapping the visible-index range onto the cluster's
  // total span as a `start..end` bar.
  const [visibleRange, setVisibleRange] = useState<{
    first: number;
    last: number;
  } | null>(null);
  const itemRefs = useRef<Array<HTMLElement | null>>([]);
  // Re-size the ref array when the entry count changes (mutate signals
  // can shrink or grow the cluster between renders). Sized in
  // useLayoutEffect, not the render body — mutating refs during render
  // re-fires under Strict Mode's double-invoke, which forces the
  // IntersectionObserver effect below to re-observe a refreshed (and
  // now-empty) ref slot every commit and lose its visibility set.
  useLayoutEffect(() => {
    if (itemRefs.current.length !== entries.length) {
      itemRefs.current = new Array<HTMLElement | null>(entries.length).fill(null);
    }
  }, [entries.length]);
  useEffect(() => {
    if (typeof IntersectionObserver === 'undefined') return;
    const visible = new Set<number>();
    const observer = new IntersectionObserver(
      (records) => {
        for (const r of records) {
          const idx = Number((r.target as HTMLElement).dataset['clusterIdx']);
          if (Number.isNaN(idx)) continue;
          if (r.isIntersecting) visible.add(idx);
          else visible.delete(idx);
        }
        // Clamp to >=1 so a half-scrolled cluster never renders "0/N";
        // the sticky header is itself proof at least one row is in view.
        setVisibleCount(Math.max(1, visible.size));
        if (visible.size > 0) {
          const sorted = Array.from(visible).sort((a, b) => a - b);
          setVisibleRange({ first: sorted[0]!, last: sorted[sorted.length - 1]! });
        } else {
          setVisibleRange(null);
        }
      },
      {
        // Threshold above 0 ensures a row barely peeking from below
        // the fold doesn't count as visible — the cue reads as the
        // number of comfortably-readable rows.
        threshold: 0.5,
      },
    );
    for (const node of itemRefs.current) {
      if (node) observer.observe(node);
    }
    return () => observer.disconnect();
  }, [entries.length]);
  // Map the visible index range onto a 0..1 progress band so the
  // underline renders as `transform: translateX(start%) scaleX(span%)`.
  // Hidden when the cluster fits in one viewport (entries.length <= 6
  // matches the count-suppression rule above — both signals fall back
  // to the static total).
  const showProgressBar = entries.length > 6 && visibleRange !== null;
  const progressStartPct = showProgressBar
    ? (visibleRange.first / entries.length) * 100
    : 0;
  const progressWidthPct = showProgressBar
    ? ((visibleRange.last - visibleRange.first + 1) / entries.length) * 100
    : 0;
  return (
    <section aria-label={t(CLUSTER_LABEL_KEY[cluster])}>
      <h3 className="sticky top-0 z-[var(--z-elevated)] mb-2 py-1 bg-[var(--surface-sticky-bg)] backdrop-blur-sm text-text-muted text-2xs font-semibold tracking-widest uppercase flex items-baseline gap-2 relative">
        <span>{t(CLUSTER_LABEL_KEY[cluster])}</span>
        <span className="text-text-muted/60 tabular-nums normal-case tracking-normal">
          {entries.length > 6
            ? `${visibleCount}/${entries.length}`
            : entries.length}
        </span>
        {showProgressBar && (
          <span
            aria-hidden="true"
            className="absolute left-0 right-0 bottom-0 h-px bg-surface-3/30 overflow-hidden"
          >
            <span
              className="block h-full bg-accent/70 transition-[transform,width] duration-200"
              style={{
                marginInlineStart: `${progressStartPct}%`,
                width: `${progressWidthPct}%`,
              }}
            />
          </span>
        )}
      </h3>
      <div className="space-y-3">
        {entries.map((entry, localIdx) => {
          const flatIdx = startIndex + localIdx;
          return (
            <div
              key={entry.key}
              ref={(node) => {
                register(flatIdx)(node);
                itemRefs.current[localIdx] = node;
              }}
              data-cluster-idx={localIdx}
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
          );
        })}
      </div>
    </section>
  );
}
