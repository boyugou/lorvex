/**
 * Issue #2755 — EisenhowerView rendered every task in every quadrant
 * inline, producing the same 500-task first-paint / scroll-jank
 * regression `ListView` already fixed via `@tanstack/react-virtual`
 * (#2211).
 *
 * These tests lock the per-quadrant virtualization contract for the
 * Eisenhower matrix:
 *   - the shared `shouldVirtualizeListView` threshold is what decides
 *     whether any single quadrant windows its rail,
 *   - a 500-task fixture distributed across the four quadrants
 *     realizes only a small window per quadrant, not the whole rail.
 *
 * Same approach as `list_view_virtualization.test.ts` — we drive
 * `@tanstack/virtual-core`'s `Virtualizer` directly with a scripted
 * scroll element.
 */

import assert from 'node:assert/strict';
import test from 'node:test';

import {
  LIST_VIEW_OVERSCAN,
  LIST_VIEW_ROW_ESTIMATE_PX,
  shouldVirtualizeListView,
} from '../../../app/src/components/list-view/virtualization';
import { Virtualizer, elementScroll } from '@tanstack/virtual-core';

// ---------------------------------------------------------------------------
// Fixture — 500 tasks distributed across the four quadrants
// ---------------------------------------------------------------------------

type QuadrantKey =
  | 'urgent_important'
  | 'not_urgent_important'
  | 'urgent_not_important'
  | 'not_urgent_not_important';

interface EisenhowerFixtureTask {
  id: string;
  quadrant: QuadrantKey;
}

const QUADRANT_ORDER: QuadrantKey[] = [
  'urgent_important',
  'not_urgent_important',
  'urgent_not_important',
  'not_urgent_not_important',
];

function buildFixture(total: number): Record<QuadrantKey, EisenhowerFixtureTask[]> {
  // Even split with a small remainder going to the last quadrant so
  // every quadrant is above the virtualization threshold (50) for a
  // 500-task fixture: 125 × 4 = 500.
  const base = Math.floor(total / 4);
  const quadrants: Record<QuadrantKey, EisenhowerFixtureTask[]> = {
    urgent_important: [],
    not_urgent_important: [],
    urgent_not_important: [],
    not_urgent_not_important: [],
  };
  let cursor = 0;
  for (let i = 0; i < QUADRANT_ORDER.length; i += 1) {
    const key = QUADRANT_ORDER[i]!;
    const count = i === QUADRANT_ORDER.length - 1 ? total - cursor : base;
    for (let j = 0; j < count; j += 1) {
      quadrants[key].push({ id: `t-${cursor}`, quadrant: key });
      cursor += 1;
    }
  }
  return quadrants;
}

function buildQuadrantVirtualizer(count: number, viewportHeightPx: number, scrollTop: number): Virtualizer<HTMLElement, HTMLElement> {
  const scrollEl = { scrollTop } as unknown as HTMLElement;
  const v = new Virtualizer<HTMLElement, HTMLElement>({
    count,
    getScrollElement: () => scrollEl,
    estimateSize: () => LIST_VIEW_ROW_ESTIMATE_PX,
    overscan: LIST_VIEW_OVERSCAN,
    observeElementRect: (_instance, cb) => {
      cb({ width: 480, height: viewportHeightPx });
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

test('Eisenhower: each quadrant above threshold is individually virtualized', () => {
  const quads = buildFixture(500);
  for (const key of QUADRANT_ORDER) {
    assert.equal(
      shouldVirtualizeListView(quads[key].length),
      quads[key].length > 50,
      `quadrant ${key} with ${quads[key].length} tasks: expected virtualize=${quads[key].length > 50}`,
    );
  }
  // Sanity: the 500-task fixture places each quadrant above 50.
  for (const key of QUADRANT_ORDER) {
    assert.ok(quads[key].length > 50, `quadrant ${key} should be above threshold`);
  }
});

test('Eisenhower: a small quadrant falls back to the plain render path', () => {
  assert.equal(shouldVirtualizeListView(1), false);
  assert.equal(shouldVirtualizeListView(25), false);
  assert.equal(shouldVirtualizeListView(50), false);
  assert.equal(shouldVirtualizeListView(51), true);
});

test('Eisenhower: per-quadrant virtualizer realizes a small window for 500 tasks', () => {
  const VIEWPORT_PX = 560; // Typical quadrant inner height.

  // 500-task quadrant — user dumped a large backlog into "not urgent
  // but important" (the strategic bucket where long lists accrue).
  const quadrant = Array.from({ length: 500 }, (_, i) => ({ id: `t-${i}`, quadrant: 'not_urgent_important' as const }));

  const v = buildQuadrantVirtualizer(quadrant.length, VIEWPORT_PX, 0);
  const items = v.getVirtualItems();

  const maxVisible = Math.ceil(VIEWPORT_PX / LIST_VIEW_ROW_ESTIMATE_PX) + LIST_VIEW_OVERSCAN * 2;

  assert.ok(items.length > 0, 'virtualizer should realize at least one row when count > 0');
  assert.ok(
    items.length <= maxVisible,
    `virtualizer realized ${items.length} rows; expected <= ${maxVisible} for a 500-task quadrant`,
  );
  assert.ok(
    items.length < quadrant.length / 10,
    `virtualizer realized ${items.length} rows; a windowed quadrant should render a small fraction of ${quadrant.length}`,
  );
  assert.equal(v.getTotalSize(), quadrant.length * LIST_VIEW_ROW_ESTIMATE_PX);
});

test('Eisenhower: quadrant windows around an arbitrary scroll position', () => {
  const VIEWPORT_PX = 560;
  const quadrant = Array.from({ length: 500 }, (_, i) => ({ id: `t-${i}`, quadrant: 'urgent_important' as const }));

  const targetIndex = 200;
  const scrollTop = targetIndex * LIST_VIEW_ROW_ESTIMATE_PX;
  const v = buildQuadrantVirtualizer(quadrant.length, VIEWPORT_PX, scrollTop);
  const items = v.getVirtualItems();

  const firstIdx = items[0]?.index ?? -1;
  const lastIdx = items[items.length - 1]?.index ?? -1;
  assert.ok(firstIdx > 0, `quadrant at scrollTop=${scrollTop} should not realize row 0`);
  assert.ok(firstIdx <= targetIndex && targetIndex <= lastIdx, `focused row ${targetIndex} should sit inside the window [${firstIdx},${lastIdx}]`);
  assert.ok(items.length < quadrant.length / 10);
});
