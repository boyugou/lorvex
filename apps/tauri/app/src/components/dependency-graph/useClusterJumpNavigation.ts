import { useEffect } from 'react';
import type { FilteredCluster } from './clustering';

interface UseClusterJumpNavigationOptions {
  filteredClusters: FilteredCluster[];
  focusedTaskId: string | null;
  setFocusedTaskId: (id: string) => void;
  /**
   * Cluster ids the user has collapsed. Required so the jump nav can
   * expand the target cluster before placing focus inside it — the
   * cluster's task rows aren't rendered while collapsed, so focusing
   * a hidden id would desync the roving-focus state from the DOM.
   */
  collapsedClusterIds: Set<string>;
  /**
   * Toggle handler keyed by cluster id. Called to expand a collapsed
   * target cluster before focus moves into it.
   */
  expandCluster: (clusterId: string) => void;
  disabled?: boolean;
}

/**
 * Adds cluster-level jump bindings on top of the existing flat
 * `useTaskListKeyboard` j/k roving focus.
 *
 *   - `Shift+j` / `Shift+ArrowDown` jumps focus to the first task of
 *     the next cluster.
 *   - `Shift+k` / `Shift+ArrowUp` jumps focus to the first task of the
 *     previous cluster.
 *
 * Plain `Tab` / `Shift+Tab` are intentionally left to the browser so
 * native focus order (header controls → task rows → action surfaces)
 * stays intact; the cluster jump uses Shift+j/k instead. Both
 * bindings are gated behind `disabled` so the hook is a no-op while
 * the view is in its loading/error state, and they early-out when
 * focus lives inside an editable surface so they don't fight inline
 * search/inputs.
 */
export function useClusterJumpNavigation({
  filteredClusters,
  focusedTaskId,
  setFocusedTaskId,
  collapsedClusterIds,
  expandCluster,
  disabled = false,
}: UseClusterJumpNavigationOptions): void {
  useEffect(() => {
    if (disabled) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.defaultPrevented) return;
      if (!event.shiftKey) return;
      if (event.metaKey || event.ctrlKey || event.altKey) return;
      const target = event.target;
      if (
        target instanceof HTMLElement &&
        (target.isContentEditable ||
          target.tagName === 'INPUT' ||
          target.tagName === 'TEXTAREA' ||
          target.tagName === 'SELECT')
      ) {
        return;
      }
      const isDown = event.key === 'J' || event.key === 'ArrowDown' || event.key === 'j';
      const isUp = event.key === 'K' || event.key === 'ArrowUp' || event.key === 'k';
      if (!isDown && !isUp) return;
      if (filteredClusters.length === 0) return;

      // Find which cluster currently owns the focused task. Default
      // to the first cluster if focus has not landed yet.
      let currentClusterIdx = 0;
      if (focusedTaskId) {
        for (let i = 0; i < filteredClusters.length; i++) {
          const cluster = filteredClusters[i];
          if (!cluster) continue;
          const found = cluster.filteredLayers.some((layer) =>
            layer.some((t) => t.id === focusedTaskId),
          );
          if (found) {
            currentClusterIdx = i;
            break;
          }
        }
      }

      const nextIdx = isDown
        ? Math.min(currentClusterIdx + 1, filteredClusters.length - 1)
        : Math.max(currentClusterIdx - 1, 0);
      if (nextIdx === currentClusterIdx && focusedTaskId) return;
      const nextCluster = filteredClusters[nextIdx];
      const firstTask = nextCluster?.filteredLayers[0]?.[0];
      if (!nextCluster || !firstTask) return;
      event.preventDefault();
      // If the destination cluster is collapsed, expand it before
      // moving focus — its task rows aren't in the DOM while
      // collapsed, so focusing a hidden id would leave the roving
      // focus ring invisible and desynced from `document.activeElement`.
      if (collapsedClusterIds.has(nextCluster.cluster.id)) {
        expandCluster(nextCluster.cluster.id);
      }
      setFocusedTaskId(firstTask.id);
    };
    window.addEventListener('keydown', onKeyDown);
    return () => { window.removeEventListener('keydown', onKeyDown); };
  }, [
    disabled,
    filteredClusters,
    focusedTaskId,
    setFocusedTaskId,
    collapsedClusterIds,
    expandCluster,
  ]);
}
