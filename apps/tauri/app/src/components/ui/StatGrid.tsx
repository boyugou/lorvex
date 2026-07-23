import type { ReactNode } from 'react';

/**
 * StatGrid — canonical responsive grid for "stat-card row" layouts.
 *
 * Extracted because the same breakpoint scheme had been
 * copy-pasted into at least three views (TodayView dashboard stats,
 * DailyReview day-summary, SnapshotPanel scope picker), and they
 * had drifted from one another:
 *
 *   - TodayView dashboard ......... `grid grid-cols-2 sm:grid-cols-3 gap-3`
 *   - DailyReview .................. `grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-3`
 *   - SnapshotPanel ................ `grid grid-cols-2 gap-2 sm:grid-cols-3` (gap-2!)
 *
 * The "right" rhythm for stat tiles is two columns on phone widths,
 * three at the `sm` (≥640px) breakpoint, and a wider step at `lg`
 * (≥1024px) when the row contains 5+ tiles — at three columns the
 * fifth+ tiles wrap awkwardly on desktop and burn vertical space. A
 * 3-tile row caps at `sm:grid-cols-3` (no `lg` step).
 *
 * The component intentionally exposes only what varies — the column
 * scheme via the `density` prop and the gap via `gap` — and keeps
 * the underlying class strings static so Tailwind v4's content scanner
 * sees them at build time (dynamic class names don't survive the
 * compiler).
 */

type StatGridDensity =
  /** Up to 3 tiles wide, no `lg` widening. Use when the row is bounded
   *  to ≤3 tiles (e.g. the Today dashboard "open / completed / someday"
   *  row). Renders `grid-cols-2 sm:grid-cols-3`. */
  | 'compact'
  /** Widens to 5 columns at the `lg` breakpoint. Use for rows of 4–5
   *  tiles (e.g. the DailyReview day-summary card). Renders
   *  `grid-cols-2 sm:grid-cols-3 lg:grid-cols-5`. */
  | 'wide';

type StatGridGap =
  /** Standard spacing — matches every existing canonical call site. */
  | 'normal'
  /** Tighter spacing for inline scope-picker style grids
   *  (SnapshotPanel) where the cells are checkboxes, not stat cards. */
  | 'tight';

interface StatGridProps {
  density: StatGridDensity;
  gap?: StatGridGap;
  className?: string;
  children: ReactNode;
}

const DENSITY_CLASSES: Record<StatGridDensity, string> = {
  compact: 'grid grid-cols-2 sm:grid-cols-3',
  wide: 'grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5',
};

const GAP_CLASSES: Record<StatGridGap, string> = {
  normal: 'gap-3',
  tight: 'gap-2',
};

export function StatGrid({
  density,
  gap = 'normal',
  className,
  children,
}: StatGridProps) {
  const cls = `${DENSITY_CLASSES[density]} ${GAP_CLASSES[gap]}${className ? ` ${className}` : ''}`;
  return <div className={cls}>{children}</div>;
}
