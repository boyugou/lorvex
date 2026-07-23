import { useCallback, useEffect, useId, useMemo, useRef, type RefObject } from 'react';
import { useVirtualizer } from '@tanstack/react-virtual';
import type { Task } from '@/lib/ipc/tasks/models';
import {
  isStringArray,
  useLocalStorageBackedState,
} from '@/lib/storage/useLocalStorageBackedState';
import { useI18n, type TranslationKey } from '../lib/i18n';
import { formatPageTitle } from '../lib/pageTitle';
import { useScrollRestore } from '../lib/useScrollRestore';
import {
  LIST_VIEW_OVERSCAN,
  shouldVirtualizeListView,
} from './list-view/virtualization';
import { FilterDropdown } from './ui/FilterDropdown';
import { ListFilterPills } from './ui/ListFilterPills';
import { TagFilterPills } from './ui/TagFilterPills';
import { PickerOverlays } from './ui/PickerOverlays';
import { LinkIcon, SearchIcon, WarningIcon } from './ui/icons';
import { Button } from './ui/Button';
import { SearchInput } from './ui/SearchInput';
import ModuleStatePanel from './ui/ModuleStatePanel';
import { Toggle } from './ui/Toggle';
import { Tooltip } from './ui/Tooltip';
import { type DepCluster } from './dependency-graph/clustering';
import { DependencyGraphViewSkeleton } from './dependency-graph/DependencyGraphViewSkeleton';
import { buildDependencyHeaderSummary } from './dependency-graph/summary';
import { useDependencyGraphController, type FilterMode } from './dependency-graph/useDependencyGraphController';
import { Cluster } from './dependency-graph/Cluster';

interface Props {
  onSelectTask?: ((taskId: string) => void) | undefined;
  /**
   * Opens QuickCapture for the header "+ Add task" button.
   * Dependencies between tasks are edited from the task-detail panel,
   * so the "add" affordance here just creates a plain task.
   */
  onAddTask?: (() => void) | undefined;
}

export default function DependencyGraphView({ onSelectTask, onAddTask }: Props) {
  const { locale, t } = useI18n();
  // Per-cluster collapse persistence — stored as a string[] of
  // collapsed cluster ids (cluster ids are stable across reloads
  // because the graph hashes a deterministic root-set). Big-project
  // users with many small clusters can park the noisy ones and only
  // expand what matters; the state survives reloads so they don't
  // have to re-collapse on every session.
  //
  // Hoisted above the controller call because Shift+J/K cluster jumps
  // (driven inside `useDependencyGraphController`) need to expand a
  // collapsed target cluster before placing focus inside it.
  const [collapsedClusterIds, setCollapsedClusterIds] = useLocalStorageBackedState<string[]>(
    'depGraphCollapsed',
    [],
    isStringArray,
  );
  const collapsedClusterSet = useMemo(
    () => new Set(collapsedClusterIds),
    [collapsedClusterIds],
  );
  const toggleClusterCollapsed = useCallback(
    (clusterId: string) => {
      setCollapsedClusterIds((prev) => {
        const set = new Set(prev);
        if (set.has(clusterId)) {
          set.delete(clusterId);
        } else {
          set.add(clusterId);
        }
        return Array.from(set);
      });
    },
    [setCollapsedClusterIds],
  );
  const expandCluster = useCallback(
    (clusterId: string) => {
      setCollapsedClusterIds((prev) => {
        if (!prev.includes(clusterId)) return prev;
        return prev.filter((id) => id !== clusterId);
      });
    },
    [setCollapsedClusterIds],
  );
  const controller = useDependencyGraphController({
    onSelectTask,
    collapsedClusterIds: collapsedClusterSet,
    expandCluster,
  });
  const scroll = useScrollRestore('dependencies');
  const hideCompletedToggleId = useId();
  // `filteredToEmpty` swaps the header primary label to a no-match
  // copy when the filter has zeroed out the visible cluster set while
  // real dependencies still exist in the dataset. Otherwise the header
  // would read "{N} tasks with dependencies" right next to a body
  // showing "No tasks match" — contradictory and confusing.
  const filteredToEmpty =
    controller.isFilterActive &&
    controller.clusters.length > 0 &&
    controller.filteredClusters.length === 0;
  const headerSummary = useMemo(
    () => buildDependencyHeaderSummary(
      locale,
      controller.totalWithDeps,
      controller.totalBlocked,
      controller.totalReady,
      t,
      filteredToEmpty,
    ),
    [controller.totalBlocked, controller.totalReady, controller.totalWithDeps, locale, t, filteredToEmpty],
  );

  // Own the scroll container so the virtualized cluster list
  // can measure against the same overflow element that
  // `useScrollRestore` already persists scrollTop on.
  const scrollContainerRef = useRef<HTMLDivElement | null>(null);
  const setScrollNode = useCallback(
    (node: HTMLDivElement | null) => {
      (scroll.ref as React.MutableRefObject<HTMLDivElement | null>).current = node;
      scrollContainerRef.current = node;
    },
    [scroll.ref],
  );

  return (
    <div className="h-full flex flex-col overflow-hidden">
      <title>{formatPageTitle(t('nav.dependencies'))}</title>
      <header className="px-4 sm:px-8 pt-1.5 pb-5 shrink-0">
        <div className="flex items-baseline justify-between">
          <div>
            <h2 className="text-text-primary text-2xl font-light">{t('deps.title')}</h2>
            <p className="text-text-muted text-xs mt-2">
              {headerSummary.primaryLabel}
              {headerSummary.statuses.map((item) => (
                <span
                  key={item.kind}
                  className={item.kind === 'blocked' ? 'text-warning' : 'text-success'}
                >
                  {' '}· {item.label}
                </span>
              ))}
            </p>
          </div>
          <div className="flex items-center gap-3">
            {controller.clusters.length > 0 && (
              <FilterDropdown<FilterMode>
                label={t('deps.filterShow')}
                value={controller.filter}
                options={[
                  { value: 'all', label: t('deps.filterAll') },
                  { value: 'blocked', label: t('deps.filterBlocked') },
                  { value: 'ready', label: t('deps.filterReady') },
                ]}
                onChange={controller.setFilter}
              />
            )}
            {onAddTask && (
              <Tooltip label={t('deps.addTaskTooltip')}>
                <Button variant="ghost" size="sm" onClick={onAddTask}>
                  + {t('deps.addTask')}
                </Button>
              </Tooltip>
            )}
          </div>
        </div>
        <SearchInput value={controller.search} onChange={controller.setSearch} placeholder={t('common.filterTasks')} className="relative mt-3 w-full max-w-sm" />
        <div className="flex items-center gap-2 mt-3 flex-wrap">
          <ListFilterPills lists={controller.lists} value={controller.filterListId} onChange={controller.setFilterListId} />
          <TagFilterPills tags={controller.allTags} selected={controller.selectedTags} onToggle={controller.toggleTag} onClear={controller.clearTagFilter} />
          <div className="flex items-center gap-1.5 ms-auto">
            <label htmlFor={hideCompletedToggleId} className="text-xs text-text-muted cursor-pointer select-none">
              {t('deps.hideCompleted')}
            </label>
            <Toggle
              id={hideCompletedToggleId}
              checked={controller.hideCompleted}
              onChange={controller.setHideCompleted}
              ariaLabel={t('deps.hideCompleted')}
            />
          </div>
        </div>
      </header>

      <div ref={setScrollNode} onScroll={scroll.onScroll} className="flex-1 overflow-y-auto overscroll-contain px-4 sm:px-8 pb-8">
        {controller.isLoading ? (
          <DependencyGraphViewSkeleton />
        ) : controller.isError ? (
          <ModuleStatePanel
            variant="error"
            icon={<WarningIcon className="w-9 h-9" />}
            title={t('common.error')}
            actionLabel={t('error.tryAgain')}
            onAction={controller.refetch}
          />
        ) : controller.clusters.length === 0 && controller.isFilterActive && controller.totalDepsExist ? (
          <ModuleStatePanel icon={<SearchIcon className="w-9 h-9" />} title={t('allTasks.emptyNoMatch')} subtitle={t('allTasks.emptySearchHint')} />
        ) : controller.clusters.length === 0 ? (
          <DependencyEmptyStoryboard t={t} onAddTask={onAddTask} />
        ) : controller.filteredClusters.length === 0 ? (
          <ModuleStatePanel icon={<SearchIcon className="w-9 h-9" />} title={t('allTasks.emptyNoMatch')} subtitle={t('allTasks.emptySearchHint')} />
        ) : shouldVirtualizeListView(
            // Count rendered task rows across all clusters' layers. Summed
            // over `filteredLayers` (post-search) and over only
            // *expanded* clusters so a search-narrowed pass — or a user
            // who has collapsed most clusters — doesn't keep
            // virtualizing rows that aren't rendering. A collapsed
            // cluster contributes nothing because the layer list under
            // its header is gone from the DOM.
            controller.filteredClusters.reduce(
              (sum, entry) =>
                sum +
                (collapsedClusterSet.has(entry.cluster.id)
                  ? 0
                  : entry.filteredLayers.flat().length),
              0,
            ),
          ) ? (
          <VirtualizedClusterList
            filteredClusters={controller.filteredClusters}
            taskMap={controller.taskMap}
            onSelectTask={onSelectTask}
            isFocused={controller.keyboard.isFocused}
            focusedTaskId={controller.keyboard.focusedId}
            scrollContainerRef={scrollContainerRef}
            locale={locale}
            t={t}
            collapsedClusterSet={collapsedClusterSet}
            onToggleClusterCollapsed={toggleClusterCollapsed}
          />
        ) : (
          <div className="space-y-8">
            {controller.filteredClusters.map(({ cluster, filteredLayers }) => (
              <Cluster
                key={cluster.id}
                cluster={cluster}
                filteredLayers={filteredLayers}
                taskMap={controller.taskMap}
                onSelectTask={onSelectTask}
                isFocused={controller.keyboard.isFocused}
                locale={locale}
                t={t}
                isCollapsed={collapsedClusterSet.has(cluster.id)}
                onToggleCollapsed={() => toggleClusterCollapsed(cluster.id)}
              />
            ))}
          </div>
        )}
      </div>

      <PickerOverlays
        tasks={controller.allFlatTasks}
        movePickerTaskId={controller.actions.movePickerTaskId}
        closeMovePickerAction={controller.actions.closeMovePickerAction}
        recurrencePickerTaskId={controller.actions.recurrencePickerTaskId}
        closeRecurrencePickerAction={controller.actions.closeRecurrencePickerAction}
        dueDatePickerTaskId={controller.actions.dueDatePickerTaskId}
        closeDueDatePickerAction={controller.actions.closeDueDatePickerAction}
        durationPickerTaskId={controller.actions.durationPickerTaskId}
        closeDurationPickerAction={controller.actions.closeDurationPickerAction}
      />
    </div>
  );
}

/**
 * Inline storyboard rendered when the dependency graph is empty.
 *
 * The "Depends on" field lives in task detail, so new users have no
 * way to discover where dependencies are created from the graph view
 * alone. The storyboard walks the three-beat flow in static type so
 * the reader can scan it without clicking anything, then offers a
 * single CTA that drops them onto a task where the actual link is
 * created.
 */
function DependencyEmptyStoryboard({
  t,
  onAddTask,
}: {
  t: (key: TranslationKey) => string;
  onAddTask?: (() => void) | undefined;
}) {
  const steps: ReadonlyArray<{ key: 'a' | 'b' | 'c'; labelKey: TranslationKey }> = [
    { key: 'a', labelKey: 'deps.emptyStoryboardStepA' },
    { key: 'b', labelKey: 'deps.emptyStoryboardStepB' },
    { key: 'c', labelKey: 'deps.emptyStoryboardStepC' },
  ];
  return (
    <div className="flex flex-col items-center justify-center py-12 sm:py-24 text-center" role="status" aria-live="polite">
      <div className="mb-4 text-text-muted/60"><LinkIcon className="w-9 h-9" /></div>
      <p className="text-text-secondary text-sm font-medium">{t('deps.empty')}</p>
      <p className="text-text-muted text-xs mt-1.5 max-w-[26rem] leading-relaxed">{t('deps.emptyHint')}</p>
      {/* 2-node "Buy paint → Paint fence" SVG illustration —
          makes the abstract dependency concept concrete before the
          reader walks the three-step storyboard. The arrow uses the
          accent-tint-xl token (alpha ~0.80) so it sits one rung below
          pure accent and reads as relationship-glue rather than louder
          than the node tiles on bright themes (Liquid blue, ember
          orange, pale mint). Node labels read live from i18n so
          localized example pairs stay in lock-step. */}
      <svg
        viewBox="0 0 280 64"
        className="mt-6 h-14 w-auto text-text-muted/70"
        role="presentation"
        aria-hidden="true"
      >
        <defs>
          <marker
            id="dep-preview-arrowhead"
            viewBox="0 0 8 8"
            refX="6"
            refY="4"
            markerWidth="6"
            markerHeight="6"
            orient="auto-start-reverse"
          >
            <path d="M0 1 L7 4 L0 7 Z" style={{ fill: 'var(--accent-tint-xl)' }} />
          </marker>
        </defs>
        <rect x="6" y="18" width="100" height="28" rx="6" className="fill-surface-2 stroke-card" strokeWidth="1.2" />
        <text x="56" y="36" textAnchor="middle" className="fill-text-primary" style={{ fontSize: '11px', fontWeight: 500 }}>
          {t('deps.emptyPreviewNodeA')}
        </text>
        <line x1="110" y1="32" x2="170" y2="32" style={{ stroke: 'var(--accent-tint-xl)' }} strokeWidth="1.5" markerEnd="url(#dep-preview-arrowhead)" />
        <rect x="174" y="18" width="100" height="28" rx="6" className="fill-surface-2 stroke-card" strokeWidth="1.2" />
        <text x="224" y="36" textAnchor="middle" className="fill-text-primary" style={{ fontSize: '11px', fontWeight: 500 }}>
          {t('deps.emptyPreviewNodeB')}
        </text>
      </svg>
      <div className="mt-6 w-full max-w-lg">
        <p className="text-2xs font-semibold tracking-widest uppercase text-text-muted/70 mb-3">
          {t('deps.emptyStoryboardTitle')}
        </p>
        <ol className="grid grid-cols-1 sm:grid-cols-3 gap-2 text-start">
          {steps.map((step, idx) => (
            <li
              key={step.key}
              className="relative rounded-r-card border border-card bg-surface-2/40 px-3.5 py-3"
            >
              <span className="absolute -top-2 -start-2 flex h-5 w-5 items-center justify-center rounded-full bg-accent text-on-accent text-2xs font-semibold shadow-[var(--shadow-tooltip)]">
                {idx + 1}
              </span>
              <span className="block text-xs leading-snug text-text-primary">{t(step.labelKey)}</span>
            </li>
          ))}
        </ol>
      </div>
      {onAddTask && (
        <button
          type="button"
          onClick={onAddTask}
          className="mt-6 text-xs px-4 py-2 rounded-r-control border border-card text-text-secondary hover:bg-surface-2 hover:border-popover active:scale-[0.97] transition-[color,background-color,border-color,transform] focus-ring-strong"
        >
          {t('deps.emptyOpenTaskCta')}
        </button>
      )}
    </div>
  );
}

/**
 * Initial height estimate for a dependency cluster card. Clusters are
 * far taller than a single task row (they render a title header plus
 * nested layered rows), so we pick an estimate that brackets a small
 * 2–3 task cluster. The real height is measured per-row via
 * `measureElement`, so this only affects the initial phantom scroll
 * range before any cluster has been laid out.
 */
const DEP_CLUSTER_ESTIMATE_PX = 240;

/**
 * Virtualized dependency-cluster list for very large graphs.
 * The dependency view is structurally a flat list of cluster cards,
 * each of which expands into a nested layer layout — so virtualizing
 * the outer list gives the same windowing win the Kanban and
 * Eisenhower views get from virtualizing their column/quadrant rails.
 * We scroll inside the view's existing outer overflow container so
 * `useScrollRestore` keeps working unchanged; each cluster is
 * rendered into an absolutely-positioned slot whose height is
 * measured once it mounts.
 */
function VirtualizedClusterList({
  filteredClusters,
  taskMap,
  onSelectTask,
  isFocused,
  focusedTaskId,
  scrollContainerRef,
  locale,
  t,
  collapsedClusterSet,
  onToggleClusterCollapsed,
}: {
  filteredClusters: Array<{ cluster: DepCluster; filteredLayers: Task[][] }>;
  taskMap: Map<string, Task>;
  onSelectTask?: ((taskId: string) => void) | undefined;
  isFocused: (taskId: string) => boolean;
  focusedTaskId: string | null;
  scrollContainerRef: RefObject<HTMLDivElement | null>;
  locale: string;
  t: (key: TranslationKey) => string;
  collapsedClusterSet: Set<string>;
  onToggleClusterCollapsed: (clusterId: string) => void;
}) {
  const virtualizer = useVirtualizer({
    count: filteredClusters.length,
    getScrollElement: () => scrollContainerRef.current,
    estimateSize: () => DEP_CLUSTER_ESTIMATE_PX,
    overscan: LIST_VIEW_OVERSCAN,
    getItemKey: (index) => filteredClusters[index]?.cluster.id ?? index,
  });

  // Map each task id to the cluster that contains it. When j/k
  // movement shifts focus across clusters we scroll the owning
  // cluster into view, matching the behaviour of the non-virtualized
  // path where every row is live in the DOM.
  const clusterIndexByTask = useMemo(() => {
    const map = new Map<string, number>();
    filteredClusters.forEach(({ cluster }, idx) => {
      for (const task of cluster.layers.flat()) {
        map.set(task.id, idx);
      }
    });
    return map;
  }, [filteredClusters]);

  useEffect(() => {
    if (!focusedTaskId) return;
    const idx = clusterIndexByTask.get(focusedTaskId);
    if (idx == null) return;
    virtualizer.scrollToIndex(idx, { align: 'auto' });
    // `useVirtualizer` returns a stable instance per
    // current `@tanstack/react-virtual`, so listing it in deps does
    // not invalidate this effect every render. If TanStack ever
    // breaks that contract, this effect will re-fire spuriously —
    // we accept that risk in exchange for not having to mirror the
    // virtualizer through a ref.
  }, [focusedTaskId, clusterIndexByTask, virtualizer]);

  return (
    <div
      className="relative w-full"
      style={{ height: `${virtualizer.getTotalSize()}px` }}
    >
      {virtualizer.getVirtualItems().map((vItem) => {
        const entry = filteredClusters[vItem.index];
        if (!entry) return null;
        return (
          <div
            key={vItem.key}
            data-index={vItem.index}
            ref={virtualizer.measureElement}
            style={{
              position: 'absolute',
              top: 0,
              left: 0,
              width: '100%',
              transform: `translateY(${vItem.start}px)`,
            }}
          >
            <div className="pb-8">
              <Cluster
                cluster={entry.cluster}
                filteredLayers={entry.filteredLayers}
                taskMap={taskMap}
                onSelectTask={onSelectTask}
                isFocused={isFocused}
                locale={locale}
                t={t}
                isCollapsed={collapsedClusterSet.has(entry.cluster.id)}
                onToggleCollapsed={() => onToggleClusterCollapsed(entry.cluster.id)}
              />
            </div>
          </div>
        );
      })}
    </div>
  );
}
