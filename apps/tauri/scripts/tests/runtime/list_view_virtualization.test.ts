/**
 * Issue #2211 — ListView / Kanban / Eisenhower / DependencyGraph render
 * every task inline without windowing. This regresses first-paint and
 * scroll performance on 500+ task lists.
 *
 * These tests lock the ListView virtualization contract:
 * - a pure threshold function decides when windowing kicks in,
 * - below the threshold nothing is virtualized (overhead outweighs
 *   benefit on small lists),
 * - above the threshold only a small visible window is rendered even
 *   when the underlying array holds 500+ tasks.
 *
 * We deliberately do not spin up a DOM here — the project's test
 * runtime is `node --test` + tsx, consistent with the other files in
 * this folder. Instead we validate the contract by driving
 * `@tanstack/virtual-core`'s `Virtualizer` class directly with a
 * scripted scroll element; that is the same engine the React hook
 * wraps, so asserting its output is a truthful proxy for what the
 * component will render.
 */

import assert from 'node:assert/strict';
import test from 'node:test';

import {
  LIST_VIEW_OVERSCAN,
  LIST_VIEW_ROW_ESTIMATE_PX,
  LIST_VIEW_VIRTUALIZATION_THRESHOLD,
  shouldVirtualizeListView,
} from '../../../app/src/components/list-view/virtualization';
import { Virtualizer, elementScroll } from '@tanstack/virtual-core';

// ---------------------------------------------------------------------------
// Threshold contract — pure, no DOM needed
// ---------------------------------------------------------------------------

test('virtualization threshold is the documented value (50)', () => {
  assert.equal(LIST_VIEW_VIRTUALIZATION_THRESHOLD, 50);
});

test('shouldVirtualizeListView is false at and below the threshold', () => {
  assert.equal(shouldVirtualizeListView(0), false);
  assert.equal(shouldVirtualizeListView(1), false);
  assert.equal(shouldVirtualizeListView(LIST_VIEW_VIRTUALIZATION_THRESHOLD), false);
});

test('shouldVirtualizeListView is true strictly above the threshold', () => {
  assert.equal(shouldVirtualizeListView(LIST_VIEW_VIRTUALIZATION_THRESHOLD + 1), true);
  assert.equal(shouldVirtualizeListView(500), true);
  assert.equal(shouldVirtualizeListView(10_000), true);
});

// ---------------------------------------------------------------------------
// Windowing contract — 500-task fixture, only a small window is realized
// ---------------------------------------------------------------------------

interface ProbeVirtualizer {
  virtualizer: Virtualizer<HTMLElement, HTMLElement>;
}

function buildProbeVirtualizer(count: number, viewportHeightPx: number, scrollTop: number): ProbeVirtualizer {
  // Minimal fake scroll element. The virtualizer only talks to it via
  // the observer callbacks we supply below, so we do not need a DOM.
  const scrollEl = { scrollTop } as unknown as HTMLElement;

  const virtualizer = new Virtualizer<HTMLElement, HTMLElement>({
    count,
    getScrollElement: () => scrollEl,
    estimateSize: () => LIST_VIEW_ROW_ESTIMATE_PX,
    overscan: LIST_VIEW_OVERSCAN,
    observeElementRect: (_instance, cb) => {
      cb({ width: 800, height: viewportHeightPx });
      return () => {};
    },
    observeElementOffset: (_instance, cb) => {
      cb(scrollEl.scrollTop, false);
      return () => {};
    },
    scrollToFn: elementScroll,
    onChange: () => {},
  });

  virtualizer._willUpdate();

  return { virtualizer };
}

test('virtualizer realizes only a small window for 500 tasks', () => {
  const TASK_COUNT = 500;
  const VIEWPORT_PX = 800;

  const { virtualizer } = buildProbeVirtualizer(TASK_COUNT, VIEWPORT_PX, 0);

  const items = virtualizer.getVirtualItems();

  // Upper bound on realized rows: ceil(viewport / rowEstimate) plus
  // overscan on both sides. At scrollTop=0 the leading overscan is
  // clipped, but keeping the simpler bound here gives us a single
  // constant that obviously dominates any reasonable implementation.
  const maxVisible = Math.ceil(VIEWPORT_PX / LIST_VIEW_ROW_ESTIMATE_PX) + LIST_VIEW_OVERSCAN * 2;

  assert.ok(
    items.length > 0,
    'virtualizer should realize at least one row when count > 0',
  );
  assert.ok(
    items.length <= maxVisible,
    `virtualizer realized ${items.length} rows; expected <= ${maxVisible} for a 500-task list`,
  );
  // And emphatically fewer than the full list — this is the whole
  // point of the change.
  assert.ok(
    items.length < TASK_COUNT / 10,
    `virtualizer realized ${items.length} rows; a windowed list should render a small fraction of ${TASK_COUNT}`,
  );

  // Total size should equal count * estimated row height before any
  // row has been measured. This is the backing "phantom" height that
  // drives the scrollbar.
  assert.equal(
    virtualizer.getTotalSize(),
    TASK_COUNT * LIST_VIEW_ROW_ESTIMATE_PX,
  );
});

test('virtualizer windows around an arbitrary scroll position', () => {
  const TASK_COUNT = 500;
  const VIEWPORT_PX = 800;

  // Put the viewport well into the middle of the list.
  const targetIndex = 300;
  const targetScrollTop = targetIndex * LIST_VIEW_ROW_ESTIMATE_PX;

  const { virtualizer } = buildProbeVirtualizer(TASK_COUNT, VIEWPORT_PX, targetScrollTop);
  const items = virtualizer.getVirtualItems();

  // Realized indices should bracket the target row, not run from 0.
  const firstIdx = items[0]?.index ?? -1;
  const lastIdx = items[items.length - 1]?.index ?? -1;

  assert.ok(
    firstIdx > 0,
    `windowed list at scrollTop=${targetScrollTop} should not realize row 0 (got firstIdx=${firstIdx})`,
  );
  assert.ok(
    firstIdx <= targetIndex && targetIndex <= lastIdx,
    `target row ${targetIndex} should be inside the realized window [${firstIdx}, ${lastIdx}]`,
  );
  assert.ok(
    items.length < TASK_COUNT / 10,
    `windowed list realized ${items.length} rows; expected a small fraction of ${TASK_COUNT}`,
  );
});
