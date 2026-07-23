import { useCallback, useMemo } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import type { TranslationKey } from '@/lib/i18n';
import {
  formatDependencyBlockedTaskCountLabel,
  formatDependencyCyclicTaskCountLabel,
  formatDependencyReadyTaskCountLabel,
  formatTaskCountLabel,
} from '../../lib/dates/i18nCountPhrases';
import {
  isDependencyGraphActiveTask,
  parseIdList,
  type DepCluster,
} from './clustering';
import { Layer } from './Layer';

/**
 * One dependency cluster: a connected component of the task-dependency
 * graph rendered as a stack of layers (root tasks at the top, blocked
 * tasks indented below). The header summarizes cluster size + counts
 * (blocked / ready / cyclic chips) so the user can scan many clusters
 * without expanding each one.
 */
export function Cluster({
  cluster,
  filteredLayers,
  taskMap,
  onSelectTask,
  isFocused,
  locale,
  t,
  isCollapsed,
  onToggleCollapsed,
}: {
  cluster: DepCluster;
  filteredLayers: Task[][];
  taskMap: Map<string, Task>;
  onSelectTask?: ((taskId: string) => void) | undefined;
  isFocused: (taskId: string) => boolean;
  locale: string;
  t: (key: TranslationKey) => string;
  /**
   * Whether this cluster is collapsed (header-only). The actual
   * collapsed-id set lives on the parent view so it can be persisted
   * to localStorage as a per-cluster map; passing the resolved bool
   * down avoids each `Cluster` reaching back into the map keyed by
   * its own id.
   */
  isCollapsed: boolean;
  /** Toggle handler bound to this cluster's id by the parent. */
  onToggleCollapsed: () => void;
}) {
  const rootTitle = cluster.roots.map((r) => r.title).join(', ');

  // Pre-memoize per-cluster derived data — flattening + dependency
  // parsing scales with cluster size, and the parent re-renders on
  // every focus/keyboard tick.
  const allDepsMap = useMemo(() => {
    const map = new Map<string, string[]>();
    for (const task of cluster.layers.flat()) {
      map.set(task.id, parseIdList(task.depends_on));
    }
    return map;
  }, [cluster.layers]);

  const clusterIds = useMemo(
    () => new Set(cluster.layers.flat().map((task) => task.id)),
    [cluster.layers],
  );

  // Terminal-status ids must be sourced from the *full* cluster, not
  // the filtered slice: a task whose dependency is a completed sibling
  // that the active filter (e.g. `hideCompleted`) has hidden is still
  // logically unblocked. Sourcing this set from `filteredLayers` would
  // misclassify it as blocked the moment its terminal dep dropped out
  // of the visible set.
  const fullClusterTerminalIds = useMemo(
    () =>
      new Set(
        cluster.layers
          .flat()
          .filter((task) => !isDependencyGraphActiveTask(task))
          .map((task) => task.id),
      ),
    [cluster.layers],
  );

  const fullClusterCyclicIds = cluster.cyclicTaskIds;

  const isBlocked = useCallback(
    (task: Task): boolean => {
      if (!isDependencyGraphActiveTask(task)) return false;
      const deps = allDepsMap.get(task.id) ?? [];
      return deps.some(
        (dep) => clusterIds.has(dep) && !fullClusterTerminalIds.has(dep),
      );
    },
    [allDepsMap, clusterIds, fullClusterTerminalIds],
  );

  // Header chip cardinality must match what the user is currently
  // looking at: when a filter narrows the rendered rows, every chip
  // counts the filtered slice. Otherwise the user reads "5 tasks · 3
  // blocked · 1 cyclic" while only 2 rows are on screen and trusts
  // neither. `Layer` still receives `cyclicTaskIds` (the full set) so
  // the per-row cyclic ring renders the same in any filter mode; only
  // the *header chip counts* shrink to match the visible rows.
  const visibleTasks = useMemo(() => filteredLayers.flat(), [filteredLayers]);
  const taskCount = visibleTasks.length;
  const blockedCount = useMemo(
    () =>
      visibleTasks.filter(
        (task) => !fullClusterCyclicIds.has(task.id) && isBlocked(task),
      ).length,
    [visibleTasks, fullClusterCyclicIds, isBlocked],
  );
  const cyclicCount = useMemo(
    () =>
      visibleTasks.filter((task) => fullClusterCyclicIds.has(task.id)).length,
    [visibleTasks, fullClusterCyclicIds],
  );
  const readyCount = useMemo(
    () =>
      visibleTasks.filter((task) => {
        if (!isDependencyGraphActiveTask(task)) return false;
        if (fullClusterCyclicIds.has(task.id)) return false;
        return !isBlocked(task);
      }).length,
    [visibleTasks, fullClusterCyclicIds, isBlocked],
  );

  const toggleLabel = isCollapsed ? t('deps.expandCluster') : t('deps.collapseCluster');
  return (
    <section className="bg-surface-2/40 border border-card rounded-r-card p-4">
      <div className="flex items-center gap-2 mb-3">
        {/* Chevron button: keyboard-activatable (Button-shaped) so users
            can collapse big clusters without reaching for the mouse.
            Rotates 90° when expanded; native title/aria reflect the
            future-tense action (the action label the click will
            trigger, not the current state). */}
        <button
          type="button"
          onClick={onToggleCollapsed}
          aria-expanded={!isCollapsed}
          aria-label={toggleLabel}
          title={toggleLabel}
          className="shrink-0 text-text-muted hover:text-text-primary rounded-r-control focus-ring-soft transition-transform duration-150"
          style={{ transform: isCollapsed ? 'rotate(0deg)' : 'rotate(90deg)' }}
        >
          <svg width="14" height="14" viewBox="0 0 16 16" aria-hidden="true" fill="none">
            <path d="M6 4 L11 8 L6 12" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </button>
        <h2 className="heading-section truncate max-w-[280px]">
          {rootTitle}
        </h2>
        <span className="text-text-muted text-xs bg-surface-3/50 px-1.5 py-0.5 rounded-r-control tabular-nums">{formatTaskCountLabel(locale, taskCount, t)}</span>
        {cyclicCount > 0 && (
          <span className="chip-warning text-xs px-1.5 py-0.5 rounded-r-control">↺ {formatDependencyCyclicTaskCountLabel(locale, cyclicCount, t)}</span>
        )}
        {blockedCount > 0 && (
          <span className="chip-warning text-xs px-1.5 py-0.5 rounded-r-control">{formatDependencyBlockedTaskCountLabel(locale, blockedCount, t)}</span>
        )}
        {readyCount > 0 && (
          <span className="chip-success text-xs px-1.5 py-0.5 rounded-r-control">{formatDependencyReadyTaskCountLabel(locale, readyCount, t)}</span>
        )}
      </div>
      {!isCollapsed && (
        <div className="space-y-3">
          {filteredLayers.map((layer, layerIdx) => (
            <Layer
              key={layer[0]?.id ?? layerIdx}
              layer={layer}
              layerIdx={layerIdx}
              cyclicTaskIds={fullClusterCyclicIds}
              allDepsMap={allDepsMap}
              taskMap={taskMap}
              clusterIds={clusterIds}
              isFocused={isFocused}
              onSelectTask={onSelectTask}
              t={t}
            />
          ))}
        </div>
      )}
    </section>
  );
}
