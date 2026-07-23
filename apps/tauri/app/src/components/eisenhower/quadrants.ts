/**
 * Ordered list of quadrant keys driving every iteration site (the matrix
 * grid render, the copy-matrix formatter, etc.). Adding a fifth quadrant
 * is a one-line edit here — no JSX duplication required.
 *
 * Declared as `as const` + derived `QuadrantKey` union so the type stays
 * tight: TS will reject any key the array doesn't list.
 */
export const QUADRANT_KEYS = [
  'urgent_important',
  'not_urgent_important',
  'urgent_not_important',
  'not_urgent_not_important',
] as const;

export type QuadrantKey = (typeof QUADRANT_KEYS)[number];

/** Tasks due within this many days (inclusive) are considered "urgent". */
export const URGENT_DAYS_THRESHOLD = 3;

export const QUADRANT_STYLE: Record<QuadrantKey, string> = {
  urgent_important: 'border-danger/40 bg-[var(--danger-tint-xs)]',
  not_urgent_important: 'border-warning/40 bg-[var(--warning-tint-xs)]',
  urgent_not_important: 'border-accent/35 bg-accent/5',
  not_urgent_not_important: 'border-surface-3 bg-surface-2/60',
};

export const DRAG_MIME = 'application/x-eisenhower-task';
