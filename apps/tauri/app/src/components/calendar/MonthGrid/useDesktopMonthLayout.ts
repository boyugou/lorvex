import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { Task } from '@/lib/ipc/tasks/models';
import { isTaskOverdue } from '@/lib/format';
import type { DayContext } from '@/lib/dayContext';
import { formatCalendarDate } from '@/lib/dates/dateLocale';

import { daysInMonth, firstDayOfWeek, toDateStr } from '../calendarViewUtils';

import { CELL_PAD_PX, DATE_HEADER_PX, ITEM_LINE_PX, MIN_ITEMS } from './constants';
import type { CellClassification } from './types';
import { TASK_STATUS } from '@lorvex/shared/types';

/**
 * Compute the dense desktop month-grid layout, the precomputed aria
 * labels keyed by ISO date, and the per-cell classification map.
 *
 * Extracted from the original DesktopMonthGrid renderer during the
 * M29 split so the imperative ResizeObserver wiring + the two memoized
 * derivations live in one focused hook instead of inline alongside the
 * JSX.
 *
 * Returns a `gridRef` the caller attaches to the outer grid element so
 * the hook's ResizeObserver can read clientHeight, plus a stable
 * snapshot of the derived data the JSX consumes per cell.
 */
export function useDesktopMonthLayout(args: {
  year: number;
  month: number;
  weekStartDay: number;
  /** Raw app locale; resolved+memoized inside `formatCalendarDate`. */
  locale: string;
  tasksByDate: Record<string, Task[]>;
  eventsByDate: Record<string, UnifiedCalendarEvent[]>;
  dayContext: DayContext;
}) {
  const { year, month, weekStartDay, locale, tasksByDate, eventsByDate, dayContext } = args;

  const firstDow = firstDayOfWeek(year, month, weekStartDay);
  const totalDays = daysInMonth(year, month);
  const cells: Array<number | null> = [
    ...Array(firstDow).fill(null),
    ...Array.from({ length: totalDays }, (_, index) => index + 1),
  ];
  while (cells.length % 7 !== 0) cells.push(null);
  const numRows = cells.length / 7;

  const gridRef = useRef<HTMLDivElement>(null);
  const [maxItems, setMaxItems] = useState(3);

  const recompute = useCallback(() => {
    const el = gridRef.current;
    if (!el) return;
    const gridHeight = el.clientHeight;
    // gap-px between rows = numRows - 1 pixels
    const rowHeight = (gridHeight - (numRows - 1)) / numRows;
    const usable = rowHeight - CELL_PAD_PX - DATE_HEADER_PX;
    const items = Math.max(MIN_ITEMS, Math.floor(usable / ITEM_LINE_PX));
    setMaxItems(items);
  }, [numRows]);

  // Pre-compute cell aria-labels once per (year, month, locale) combo.
  // `formatCalendarDate` routes through the shared memoized formatter
  // cache in `lib/dateLocale`, so a 42-cell month × 42-cell re-renders
  // during a drag sweep amortizes to one `Intl.DateTimeFormat`
  // construction across the whole calendar surface (vs. one per
  // (year,month) before the cache).
  const ariaLabelByDateStr = useMemo(() => {
    const labels: Record<string, string> = {};
    for (let d = 1; d <= totalDays; d += 1) {
      const dateStr = toDateStr(year, month, d);
      labels[dateStr] = formatCalendarDate(dateStr, locale, {
        weekday: 'long', month: 'long', day: 'numeric',
      });
    }
    return labels;
  }, [year, month, totalDays, locale]);

  // precompute every cell's task / event classification
  // once per (tasksByDate, eventsByDate, maxItems, dayContext) tuple.
  // The previous shape ran `dayTasks.some/.filter/.filter/.slice` for
  // every cell on every render — during a drag sweep across a 42-cell
  // month grid, every drag-over event re-ran 42 cells × 4 array passes
  // × N tasks per day. By materializing the classification up here,
  // unrelated re-renders (drag-over state flip on a single cell) no
  // longer touch the inner loops. Cell render becomes an O(1) map
  // lookup.
  const classificationByDateStr = useMemo(() => {
    const out: Record<string, CellClassification> = {};
    for (let d = 1; d <= totalDays; d += 1) {
      const dateStr = toDateStr(year, month, d);
      const dayTasks = tasksByDate[dateStr] ?? [];
      const dayEvents = eventsByDate[dateStr] ?? [];
      let hasOverdue = false;
      const openTasks: Task[] = [];
      const completedTasks: Task[] = [];
      // Single pass over dayTasks to populate three buckets.
      for (const task of dayTasks) {
        if (task.status === TASK_STATUS.completed) {
          completedTasks.push(task);
        } else if (task.status === TASK_STATUS.open) {
          openTasks.push(task);
          if (!hasOverdue && isTaskOverdue(task, dayContext)) {
            hasOverdue = true;
          }
        }
      }
      const shownEvents = dayEvents.slice(0, maxItems);
      const remainingSlots = maxItems - shownEvents.length;
      const shownTasks = openTasks.slice(0, Math.max(0, remainingSlots));
      const totalHidden =
        (dayEvents.length - shownEvents.length) + (openTasks.length - shownTasks.length);
      out[dateStr] = {
        hasOverdue,
        openTasks,
        completedTasks,
        shownEvents,
        shownTasks,
        totalHidden,
      };
    }
    return out;
  }, [tasksByDate, eventsByDate, maxItems, dayContext, year, month, totalDays]);

  useEffect(() => {
    recompute();
    const el = gridRef.current;
    if (!el) return;
    const observer = new ResizeObserver(recompute);
    observer.observe(el);
    return () => observer.disconnect();
  }, [recompute]);

  return {
    gridRef,
    cells,
    numRows,
    ariaLabelByDateStr,
    classificationByDateStr,
  };
}
