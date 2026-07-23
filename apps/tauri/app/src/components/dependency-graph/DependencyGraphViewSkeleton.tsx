/**
 * DependencyGraphViewSkeleton — graph-shaped placeholder for the
 * Dependency Graph view while the cluster query is loading.
 *
 * The real view renders a vertical stack of cluster cards; each
 * cluster has a header chip row plus nested layered task rows
 * connected by a small "depends on" arrow SVG. The skeleton mirrors
 * the cluster card geometry, and adds a small animated SVG node-edge
 * graph in the first cluster header to evoke "graph loading" instead
 * of just "list loading".
 *
 * Reduced-motion handling:
 *   - The shimmer (`motion-safe:animate-pulse`) is gated by Tailwind's
 *     built-in reduced-motion media query.
 *   - The SVG node pulse animations are wrapped in `motion-safe:` too,
 *     so reduced-motion users see a static node-edge silhouette.
 */

import { useI18n } from '@/lib/i18n';
import { Bar } from '../ui/SkeletonShimmer';

/**
 * A small DAG silhouette: 4 nodes, 3 curved edges. Drawn in
 * surface-3-toned strokes/fills so it reads as a placeholder rather
 * than active content. Each node has a subtle pulse animation gated
 * by `motion-safe:` (CSS animation utilities below assume Tailwind
 * v4's `motion-safe:` prefix maps to `@media (prefers-reduced-motion: no-preference)`).
 */
function GraphSilhouette() {
  return (
    <svg
      width="120"
      height="40"
      viewBox="0 0 120 40"
      className="text-surface-3 shrink-0"
      aria-hidden="true"
    >
      {/* Edges — curved Beziers between node centers */}
      <path
        d="M 12 20 Q 30 6 50 20"
        stroke="currentColor"
        strokeWidth="1.5"
        fill="none"
        strokeLinecap="round"
      />
      <path
        d="M 50 20 Q 68 34 88 20"
        stroke="currentColor"
        strokeWidth="1.5"
        fill="none"
        strokeLinecap="round"
      />
      <path
        d="M 50 20 Q 80 6 108 20"
        stroke="currentColor"
        strokeWidth="1.5"
        fill="none"
        strokeLinecap="round"
      />

      {/* Nodes — staggered pulse animations so the graph "breathes" */}
      <circle
        cx="12"
        cy="20"
        r="5"
        fill="currentColor"
        className="motion-safe:animate-pulse"
        style={{ animationDelay: '0ms' }}
      />
      <circle
        cx="50"
        cy="20"
        r="5"
        fill="currentColor"
        className="motion-safe:animate-pulse"
        style={{ animationDelay: '180ms' }}
      />
      <circle
        cx="88"
        cy="20"
        r="5"
        fill="currentColor"
        className="motion-safe:animate-pulse"
        style={{ animationDelay: '360ms' }}
      />
      <circle
        cx="108"
        cy="20"
        r="5"
        fill="currentColor"
        className="motion-safe:animate-pulse"
        style={{ animationDelay: '540ms' }}
      />
    </svg>
  );
}

function ClusterRow({ widthClass, indent = 0 }: { widthClass: string; indent?: number }) {
  return (
    <div className={`${indent > 0 ? 'ms-8 ps-3 border-s-2 border-surface-3' : ''}`}>
      <div className="rounded-r-card border border-card bg-surface-2/40 px-4 py-3 flex items-center gap-3">
        <Bar className="h-4 w-4 rounded-full shrink-0" />
        <Bar className={`h-4 ${widthClass}`} />
      </div>
    </div>
  );
}

function ClusterCard({ withGraph = false }: { withGraph?: boolean }) {
  return (
    <section className="bg-surface-2/40 border border-card rounded-r-card p-4">
      {/* Cluster header — title + count chip(s), optionally with the
          graph silhouette tucked to the right to evoke "this is a DAG". */}
      <div className="flex items-center justify-between gap-2 mb-3">
        <div className="flex items-center gap-2">
          <Bar className="h-4 w-40" />
          <Bar className="h-3 w-10 rounded-r-control" />
          <Bar className="h-3 w-12 rounded-r-control" />
        </div>
        {withGraph && <GraphSilhouette />}
      </div>

      {/* Layered task rows. Layer 1 is the root, layer 2 is indented
          and prefixed with the "depends on" border-accent gutter. */}
      <div className="space-y-3">
        <div className="space-y-1.5">
          <ClusterRow widthClass="w-3/4" />
          <ClusterRow widthClass="w-2/3" />
        </div>
        <div className="space-y-1.5">
          {/* "depends on" arrow row */}
          <div className="flex items-center gap-2 ms-2 px-4">
            <Bar className="h-4 w-4 rounded-full" />
            <Bar className="h-3 w-20" />
          </div>
          <ClusterRow widthClass="w-1/2" indent={1} />
          <ClusterRow widthClass="w-3/5" indent={1} />
        </div>
      </div>
    </section>
  );
}

export function DependencyGraphViewSkeleton() {
  const { t } = useI18n();
  return (
    <div
      className="space-y-8 motion-safe:animate-pulse"
      role="status"
      aria-label={t('common.loading')}
    >
      <ClusterCard withGraph />
      <ClusterCard />
    </div>
  );
}
