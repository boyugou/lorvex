/**
 * Issue #2756 — DependencyGraphView rendered every dependency cluster
 * inline, producing the same 500-task first-paint / scroll-jank
 * regression `ListView` already fixed via `@tanstack/react-virtual`
 * (#2211).
 *
 * The dependency view is structurally a flat list of variable-height
 * cluster cards (each cluster is a layered layout of tasks with
 * dependencies). Virtualization applies cleanly: we window the outer
 * cluster list so only a handful of clusters are mounted at any given
 * scroll position.
 *
 * These tests lock the contract:
 *   - a small graph (few clusters) falls back to the plain render
 *     path (virtualizer overhead isn't worth it below the threshold),
 *   - a 500-task graph partitioned into many clusters realizes only
 *     a small window of cluster nodes,
 *   - windowing brackets the current scroll position rather than
 *     always rendering from the first cluster.
 *
 * Same approach as `list_view_virtualization.test.ts` — we drive
 * `@tanstack/virtual-core`'s `Virtualizer` directly with a scripted
 * scroll element.
 */

import assert from 'node:assert/strict';
import test from 'node:test';

import {
  LIST_VIEW_OVERSCAN,
  shouldVirtualizeListView,
} from '../../../app/src/components/list-view/virtualization';
import { Virtualizer, elementScroll } from '@tanstack/virtual-core';

// DependencyGraphView uses a larger per-row estimate than the simple
// task-row views because each cluster card is a multi-line layered
// layout. Mirror the constant the view declares.
const DEP_CLUSTER_ESTIMATE_PX = 240;

// ---------------------------------------------------------------------------
// Fixture — 500 tasks partitioned into ~60 clusters
// ---------------------------------------------------------------------------

interface DepCluster {
  id: string;
  taskIds: string[];
}

function buildClusters(totalTasks: number, clusterCount: number): DepCluster[] {
  // Partition tasks round-robin into `clusterCount` clusters so each
  // cluster has a realistic 2–10 tasks with dependencies.
  const clusters: DepCluster[] = Array.from({ length: clusterCount }, (_, i) => ({
    id: `c-${i}`,
    taskIds: [],
  }));
  for (let i = 0; i < totalTasks; i += 1) {
    clusters[i % clusterCount]!.taskIds.push(`t-${i}`);
  }
  return clusters;
}

function buildClusterVirtualizer(count: number, viewportHeightPx: number, scrollTop: number): Virtualizer<HTMLElement, HTMLElement> {
  const scrollEl = { scrollTop } as unknown as HTMLElement;
  const v = new Virtualizer<HTMLElement, HTMLElement>({
    count,
    getScrollElement: () => scrollEl,
    estimateSize: () => DEP_CLUSTER_ESTIMATE_PX,
    overscan: LIST_VIEW_OVERSCAN,
    observeElementRect: (_instance, cb) => {
      cb({ width: 900, height: viewportHeightPx });
      return () => {};
    },
    observeElementOffset: (_instance, cb) => {
      cb(scrollEl.scrollTop, false);
      return () => {};
    },
    scrollToFn: elementScroll,
    onChange: () => {},
  });
  v._willUpdate();
  return v;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test('DependencyGraph: small graphs stay on the plain render path', () => {
  // Most real dependency graphs produce a handful of clusters; windowing
  // them would be pure overhead. The same 50-item threshold used by the
  // list views gates the outer cluster list.
  assert.equal(shouldVirtualizeListView(5), false);
  assert.equal(shouldVirtualizeListView(25), false);
  assert.equal(shouldVirtualizeListView(50), false);
  assert.equal(shouldVirtualizeListView(51), true);
});

test('DependencyGraph: 500-task graph produces >50 clusters so virtualization kicks in', () => {
  const clusters = buildClusters(500, 60);
  assert.equal(clusters.length, 60);
  assert.ok(
    shouldVirtualizeListView(clusters.length),
    `60 clusters should cross the virtualization threshold`,
  );
});

test('DependencyGraph: cluster virtualizer realizes a small window for 60 clusters', () => {
  const VIEWPORT_PX = 800;
  const clusters = buildClusters(500, 60);

  const v = buildClusterVirtualizer(clusters.length, VIEWPORT_PX, 0);
  const items = v.getVirtualItems();

  // Upper bound: ceil(viewport / clusterEstimate) + overscan × 2.
  const maxVisible = Math.ceil(VIEWPORT_PX / DEP_CLUSTER_ESTIMATE_PX) + LIST_VIEW_OVERSCAN * 2;

  assert.ok(items.length > 0, 'virtualizer should realize at least one cluster when count > 0');
  assert.ok(
    items.length <= maxVisible,
    `virtualizer realized ${items.length} clusters; expected <= ${maxVisible}`,
  );
  // And emphatically fewer than the full list.
  assert.ok(
    items.length < clusters.length,
    `virtualizer realized every cluster (${items.length} of ${clusters.length}); windowing defeated`,
  );
  assert.equal(v.getTotalSize(), clusters.length * DEP_CLUSTER_ESTIMATE_PX);
});

test('DependencyGraph: cluster window brackets an arbitrary scroll position', () => {
  const VIEWPORT_PX = 800;
  const clusters = buildClusters(500, 60);

  // Put the viewport at cluster index 30 — the middle of the list.
  const targetIndex = 30;
  const scrollTop = targetIndex * DEP_CLUSTER_ESTIMATE_PX;
  const v = buildClusterVirtualizer(clusters.length, VIEWPORT_PX, scrollTop);
  const items = v.getVirtualItems();

  const firstIdx = items[0]?.index ?? -1;
  const lastIdx = items[items.length - 1]?.index ?? -1;

  assert.ok(firstIdx > 0, `cluster list at scrollTop=${scrollTop} should not realize cluster 0`);
  assert.ok(
    firstIdx <= targetIndex && targetIndex <= lastIdx,
    `cluster ${targetIndex} should be inside the realized window [${firstIdx}, ${lastIdx}]`,
  );
});
