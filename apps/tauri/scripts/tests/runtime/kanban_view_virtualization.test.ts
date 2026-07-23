/**
 * Issue #2754 — KanbanView rendered every task in every column
 * inline, producing the same 500-task first-paint / scroll-jank
 * regression `ListView` already fixed via `@tanstack/react-virtual`
 * (#2211).
 *
 * These tests lock the per-column virtualization contract for Kanban:
 *   - the shared `shouldVirtualizeListView` threshold is what decides
 *     whether any single column windows its rail,
 *   - a 500-task fixture distributed across the three Kanban columns
 *     realizes only a small window per column, not the whole rail.
 *
 * Same approach as `list_view_virtualization.test.ts` — we drive
 * `@tanstack/virtual-core`'s `Virtualizer` directly with a scripted
 * scroll element instead of spinning up a DOM. That is the engine the
 * React hook wraps, so asserting its output is a truthful proxy for
 * what the component will render.
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
// Fixture — 500 tasks distributed across Kanban's three columns
// ---------------------------------------------------------------------------

type ColumnKey = 'open' | 'someday' | 'completed';

interface KanbanFixtureTask {
  id: string;
  column: ColumnKey;
}

function buildFixture(total: number): Record<ColumnKey, KanbanFixtureTask[]> {
  // Realistic-ish distribution: most tasks are active, some parked in
  // "someday", and a tail of completed. Numbers chosen so each column
  // is individually above the virtualization threshold (50).
  const counts: Record<ColumnKey, number> = {
    open: Math.floor(total * 0.6),
    someday: Math.floor(total * 0.2),
    completed: 0,
  };
  counts.completed = total - counts.open - counts.someday;

  const columns: Record<ColumnKey, KanbanFixtureTask[]> = {
    open: [],
    someday: [],
    completed: [],
  };
  let cursor = 0;
  for (const key of ['open', 'someday', 'completed'] as ColumnKey[]) {
    for (let i = 0; i < counts[key]; i += 1) {
      columns[key].push({ id: `t-${cursor}`, column: key });
      cursor += 1;
    }
  }
  return columns;
}

function buildColumnVirtualizer(count: number, viewportHeightPx: number, scrollTop: number): Virtualizer<HTMLElement, HTMLElement> {
  const scrollEl = { scrollTop } as unknown as HTMLElement;
  const v = new Virtualizer<HTMLElement, HTMLElement>({
    count,
    getScrollElement: () => scrollEl,
    estimateSize: () => LIST_VIEW_ROW_ESTIMATE_PX,
    overscan: LIST_VIEW_OVERSCAN,
    observeElementRect: (_instance, cb) => {
      cb({ width: 320, height: viewportHeightPx });
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

test('Kanban: each column above threshold is individually virtualized', () => {
  const cols = buildFixture(500);
  for (const key of Object.keys(cols) as ColumnKey[]) {
    assert.equal(
      shouldVirtualizeListView(cols[key].length),
      cols[key].length > 50,
      `column ${key} with ${cols[key].length} tasks: expected virtualize=${cols[key].length > 50}`,
    );
  }
  // Sanity: the 500-task fixture places each column above 50 so the
  // "all three columns virtualize" branch is exercised.
  assert.ok(cols.open.length > 50);
  assert.ok(cols.someday.length > 50);
  assert.ok(cols.completed.length > 50);
});

test('Kanban: a small column falls back to the plain render path', () => {
  // Small boards are the common case. The virtualizer overhead isn't
  // worth it below 50 rows — we assert the per-column predicate matches
  // the threshold contract the shared helper encodes.
  assert.equal(shouldVirtualizeListView(1), false);
  assert.equal(shouldVirtualizeListView(10), false);
  assert.equal(shouldVirtualizeListView(50), false);
  assert.equal(shouldVirtualizeListView(51), true);
});

test('Kanban: per-column virtualizer realizes a small window for 500 tasks', () => {
  const VIEWPORT_PX = 640; // Typical kanban-column inner height.

  // Single 500-task column — the pathological case for a deep backlog
  // dumped into "open". Even here only a small window should render.
  const column = Array.from({ length: 500 }, (_, i) => ({ id: `t-${i}`, column: 'open' as const }));

  const v = buildColumnVirtualizer(column.length, VIEWPORT_PX, 0);
  const items = v.getVirtualItems();

  const maxVisible = Math.ceil(VIEWPORT_PX / LIST_VIEW_ROW_ESTIMATE_PX) + LIST_VIEW_OVERSCAN * 2;

  assert.ok(items.length > 0, 'virtualizer should realize at least one row when count > 0');
  assert.ok(
    items.length <= maxVisible,
    `virtualizer realized ${items.length} rows; expected <= ${maxVisible} for a 500-task column`,
  );
  assert.ok(
    items.length < column.length / 10,
    `virtualizer realized ${items.length} rows; a windowed column should render a small fraction of ${column.length}`,
  );
  assert.equal(v.getTotalSize(), column.length * LIST_VIEW_ROW_ESTIMATE_PX);
});

test('Kanban: column windows around an arbitrary scroll position', () => {
  const VIEWPORT_PX = 640;
  const column = Array.from({ length: 500 }, (_, i) => ({ id: `t-${i}`, column: 'open' as const }));

  const targetIndex = 250;
  const scrollTop = targetIndex * LIST_VIEW_ROW_ESTIMATE_PX;
  const v = buildColumnVirtualizer(column.length, VIEWPORT_PX, scrollTop);
  const items = v.getVirtualItems();

  const firstIdx = items[0]?.index ?? -1;
  const lastIdx = items[items.length - 1]?.index ?? -1;
  assert.ok(firstIdx > 0, `column at scrollTop=${scrollTop} should not realize row 0`);
  assert.ok(firstIdx <= targetIndex && targetIndex <= lastIdx, `focused row ${targetIndex} should sit inside the window [${firstIdx},${lastIdx}]`);
  assert.ok(items.length < column.length / 10);
});
