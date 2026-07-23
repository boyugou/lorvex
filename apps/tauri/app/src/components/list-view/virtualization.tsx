/**
 * Virtualization support for the list view's open task rail.
 *
 * rendering 500+ tasks with an unconditional `.map(...)`
 * produced noticeable scroll jank and slow first paint on large lists.
 * We window the rendering through `@tanstack/react-virtual`, but only
 * past a threshold — for short lists the virtualizer's measurement
 * overhead outweighs the benefit and can make ordinary navigation feel
 * sluggish on low-end hardware.
 *
 * This module is the pure, testable surface: constants + a helper that
 * decides whether a given list should be virtualized. Keeping it
 * framework-free means the runtime test harness (node --test) can
 * assert the contract without bringing in a DOM.
 */

/**
 * Below this row count the standard non-virtualized render is faster
 * overall. The figure is a product call, not a theoretical limit —
 * around 50 rows the virtualizer's measurement passes start costing
 * more than they save on the kinds of laptops Lorvex targets.
 */
export const LIST_VIEW_VIRTUALIZATION_THRESHOLD = 50;

/**
 * Initial row height estimate handed to `useVirtualizer`. The real
 * height is measured per-row via `measureElement`, so this value only
 * affects the size of the initially-painted window before any row has
 * been laid out. 64px matches a single-line task card with some
 * breathing room; multi-line cards grow beyond this on first measure.
 */
export const LIST_VIEW_ROW_ESTIMATE_PX = 64;

/**
 * Overscan rows kept mounted above/below the visible window. Too small
 * and fast scrolls flash empty space; too large and we defeat the
 * purpose of virtualizing. 10 rows is the same figure AllTasksView
 * settled on.
 */
export const LIST_VIEW_OVERSCAN = 10;

/** True when virtualization should be used for `count` rows. */
export function shouldVirtualizeListView(count: number): boolean {
  return count > LIST_VIEW_VIRTUALIZATION_THRESHOLD;
}

import { useCallback, useEffect, useMemo, useRef } from 'react';
import { useVirtualizer, type VirtualItem } from '@tanstack/react-virtual';
import type { Task } from '@/lib/ipc/tasks/models';

interface VirtualizedTaskColumnState {
  scrollRef: React.RefObject<HTMLDivElement | null>;
  virtualItems: VirtualItem[];
  totalSize: number;
  measureElement: (node: Element | null) => void;
}

export function useVirtualizedTaskColumn(
  tasks: Task[],
  focusedTaskId: string | null,
): VirtualizedTaskColumnState {
  const scrollRef = useRef<HTMLDivElement | null>(null);
  const virtualizer = useVirtualizer({
    count: tasks.length,
    getScrollElement: () => scrollRef.current,
    estimateSize: () => LIST_VIEW_ROW_ESTIMATE_PX,
    overscan: LIST_VIEW_OVERSCAN,
    getItemKey: (index) => tasks[index]?.id ?? index,
  });

  const taskIndexById = useMemo(() => {
    const map = new Map<string, number>();
    tasks.forEach((task, idx) => map.set(task.id, idx));
    return map;
  }, [tasks]);

  useEffect(() => {
    if (!focusedTaskId) return;
    const idx = taskIndexById.get(focusedTaskId);
    if (idx == null) return;
    virtualizer.scrollToIndex(idx, { align: 'auto' });
    // `useVirtualizer` returns a stable instance under current
    // `@tanstack/react-virtual`, so listing it in deps does not
    // invalidate this effect every render.
  }, [focusedTaskId, taskIndexById, virtualizer]);

  return {
    scrollRef,
    virtualItems: virtualizer.getVirtualItems(),
    totalSize: virtualizer.getTotalSize(),
    measureElement: virtualizer.measureElement,
  };
}

// ---------------------------------------------------------------------------
// Section-row variant for AllTasks (mixed task + section-header + gap rows).
// ---------------------------------------------------------------------------
//
// AllTasksView windows a heterogeneous row stream — section headers, task
// rows, and inter-section gaps — so the simpler `useVirtualizedTaskColumn`
// hook above (uniform task rows) is not a fit. Task rows are
// wrapping flex layouts whose final height depends on title length, the
// presence of meta pills (due / tags / duration), and locale; the flat
// `TASK_ROW_HEIGHT` estimate caused visible scrollbar-thumb drift the
// first time a long-title row entered the viewport (`measureElement`
// would correct the height, shifting subsequent rows down by tens of
// px). Storing the measured size keyed by task id means once a row has
// been seen, its size estimate is exact on every later virtualization
// pass — even after a re-sort blows away the virtualizer's
// index-keyed internal cache.

/**
 * Tagged-union row kind a caller of `useVirtualizedTaskRows` provides.
 * Mirrors AllTasksView's pre-refactor `VirtualRow` shape; kept narrow
 * so the hook stays oblivious to caller-specific row payloads.
 */
export type VirtualizedSectionRow =
  | { kind: 'task'; taskId: string }
  | { kind: 'section-header' }
  | { kind: 'section-gap' };

interface UseVirtualizedTaskRowsArgs {
  rows: VirtualizedSectionRow[];
  /** Element used by `getScrollElement`; AllTasks merges this with `useScrollRestore`. */
  scrollRef: React.RefObject<HTMLDivElement | null>;
  /** Flat estimate (in px) for section-header rows. */
  headerHeight: number;
  /** Flat estimate (in px) for inter-section gap rows. */
  sectionGapHeight: number;
  /** Initial estimate (in px) for task rows that haven't been measured yet. */
  taskRowEstimate: number;
  /** Optional focused task id; the hook scrolls the row index into view on change. */
  focusedTaskId: string | null;
  /** Overscan rows kept mounted above/below the visible window. */
  overscan?: number;
}

interface VirtualizedTaskRowsState {
  virtualItems: VirtualItem[];
  totalSize: number;
  measureElement: (node: Element | null) => void;
}

export function useVirtualizedTaskRows({
  rows,
  scrollRef,
  headerHeight,
  sectionGapHeight,
  taskRowEstimate,
  focusedTaskId,
  overscan = LIST_VIEW_OVERSCAN,
}: UseVirtualizedTaskRowsArgs): VirtualizedTaskRowsState {
  // Per-task measured-height cache. We only memoize task
  // rows — section headers and gaps are flat heights, no measurement
  // needed.
  const measuredTaskHeightsRef = useRef<Map<string, number>>(new Map());

  const estimateSize = useCallback(
    (index: number) => {
      const row = rows[index];
      if (!row) return taskRowEstimate;
      switch (row.kind) {
        case 'section-header':
          return headerHeight;
        case 'section-gap':
          return sectionGapHeight;
        case 'task':
          return measuredTaskHeightsRef.current.get(row.taskId) ?? taskRowEstimate;
      }
    },
    [rows, headerHeight, sectionGapHeight, taskRowEstimate],
  );

  // Hold the live virtualizer in a ref so the wrapped
  // `measureElement` defined below can forward measurements to it
  // without depending on TDZ ordering (the `useCallback` runs every
  // render before the `useVirtualizer` call completes). Narrow the
  // ref type to just the call surface we need; the full parametric
  // `Virtualizer<HTMLDivElement, Element>` type is hard to spell at
  // the binding site (TanStack's generics are inferred off the call
  // shape, not the return type).
  const virtualizerRef = useRef<{ measureElement: (node: Element | null) => void } | null>(null);

  /**
   * Wraps the virtualizer's `measureElement` so each measured task
   * row also lands in our id-keyed cache. The virtualizer's internal
   * cache is index-keyed and dropped whenever the row order changes
   * (filter/sort/group), so without this map a re-sorted list would
   * be back to the flat estimate. Section headers / gaps still call
   * the underlying measurer so the virtualizer's own accounting
   * stays correct.
   */
  const measureElement = useCallback(
    (node: Element | null) => {
      if (!node) return;
      const indexAttr = (node as HTMLElement).dataset?.index;
      if (indexAttr !== undefined) {
        const idx = Number(indexAttr);
        const row = rows[idx];
        if (row?.kind === 'task') {
          const h = (node as HTMLElement).offsetHeight;
          if (h > 0) {
            const cached = measuredTaskHeightsRef.current.get(row.taskId);
            if (cached !== h) measuredTaskHeightsRef.current.set(row.taskId, h);
          }
        }
      }
      virtualizerRef.current?.measureElement(node);
    },
    [rows],
  );

  const virtualizer = useVirtualizer({
    count: rows.length,
    getScrollElement: () => scrollRef.current,
    estimateSize,
    overscan,
  });
  virtualizerRef.current = virtualizer;

  // Keyboard navigation: scroll the focused task's row into view. The
  // generic `useTaskListKeyboard` hook uses DOM `scrollIntoView`,
  // which fails for virtualised rows that aren't currently rendered.
  // Map the focused id to its virtual row index and let the
  // virtualizer handle the scroll instead.
  useEffect(() => {
    if (!focusedTaskId) return;
    const rowIndex = rows.findIndex(
      (r) => r.kind === 'task' && r.taskId === focusedTaskId,
    );
    if (rowIndex >= 0) {
      virtualizer.scrollToIndex(rowIndex, { align: 'auto' });
    }
    // `useVirtualizer` returns a stable instance per current
    // `@tanstack/react-virtual`, so listing it in deps does not
    // invalidate this effect every render. If TanStack ever breaks
    // that contract, this effect will re-fire spuriously — we accept
    // that risk in exchange for not having to mirror the virtualizer
    // through a ref.
  }, [focusedTaskId, rows, virtualizer]);

  return {
    virtualItems: virtualizer.getVirtualItems(),
    totalSize: virtualizer.getTotalSize(),
    measureElement,
  };
}
