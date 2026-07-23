import { memo, type ReactNode } from 'react';

/*
 * `<TonalIconBubble>` primitive.
 *
 * The "circular tinted icon container" recipe —
 *
 *   w-{n} h-{n} rounded-full plus the tone tint-sm background token
 *   flex items-center justify-center
 *
 * — was hand-rolled in 6+ places: ErrorBoundary's danger badge,
 * SaveStreakSection's flame, DaySummarySection's per-task check,
 * StatCard's tone icon (via ICON_BG_MAP), among others. Each one drifted
 * in subtle ways (tint step, icon-colour pairing, square vs circle).
 * Pulling the recipe into a per-tone primitive keeps the bubbles
 * marching to one rhythm.
 *
 * Sizing pairs:
 *   - `xs` →  w-4  h-4   (inline-row checkmarks, e.g. DaySummarySection)
 *   - `sm` →  w-8  h-8   (StatCard icon, popover badges)
 *   - `md` →  w-10 h-10
 *   - `lg` →  w-12 h-12  (empty-state hero, ErrorBoundary danger badge)
 *
 * Tint pairs:
 *   - `xs` (default for `xs/sm` bubbles) — tone tint-xs background
 *   - `sm` — tone tint-sm background (default for `md/lg` bubbles)
 *   - `md` — tone tint-md background for prominent emphasis
 *
 * The icon child should drive its own colour (`text-{tone}` or
 * `currentColor` if it inherits). The primitive only owns the shell.
 */

type TonalIconBubbleTone = 'success' | 'warning' | 'danger' | 'accent' | 'muted';
type TonalIconBubbleSize = 'xs' | 'sm' | 'md' | 'lg';
type TonalIconBubbleTint = 'xs' | 'sm' | 'md';

const SIZE_CLASS: Record<TonalIconBubbleSize, string> = {
  xs: 'w-4 h-4',
  sm: 'w-8 h-8',
  md: 'w-10 h-10',
  lg: 'w-12 h-12',
};

// Per-tone fill at each tint step. The accent tone uses the
// `--accent-tint-*` ladder; the four semantic tones use their own
// `--{tone}-tint-*` ladders; muted falls back to surface-3.
const TINT_CLASS: Record<TonalIconBubbleTone, Record<TonalIconBubbleTint, string>> = {
  success: {
    xs: 'bg-[var(--success-tint-xs)]',
    sm: 'bg-[var(--success-tint-sm)]',
    md: 'bg-[var(--success-tint-md)]',
  },
  warning: {
    xs: 'bg-[var(--warning-tint-xs)]',
    sm: 'bg-[var(--warning-tint-sm)]',
    md: 'bg-[var(--warning-tint-md)]',
  },
  danger: {
    xs: 'bg-[var(--danger-tint-xs)]',
    sm: 'bg-[var(--danger-tint-sm)]',
    md: 'bg-[var(--danger-tint-md)]',
  },
  accent: {
    xs: 'bg-[var(--accent-tint-xs)]',
    sm: 'bg-[var(--accent-tint-sm)]',
    md: 'bg-[var(--accent-tint-md)]',
  },
  muted: {
    xs: 'bg-surface-2',
    sm: 'bg-surface-3/60',
    md: 'bg-surface-3',
  },
};

interface TonalIconBubbleProps {
  tone: TonalIconBubbleTone;
  size?: TonalIconBubbleSize;
  /** Tint step. Defaults: xs/sm bubbles → `xs`; md/lg bubbles → `sm`. */
  tint?: TonalIconBubbleTint;
  /** Icon node. Should colour itself via `text-{tone}` or currentColor. */
  children: ReactNode;
  /** Extra utility classes (e.g. `mb-4`, `shrink-0`). */
  className?: string;
  /*
   * Accessibility contract. The bubble is decorative by default —
   * every consumer either pairs it with adjacent text or wraps it
   * in an `aria-label`-bearing button — so a screen reader should
   * skip it. When the icon stands alone and IS meaningful (rare,
   * but possible), pass `aria-label`; we drop the `aria-hidden`
   * and forward the label so AT users hear the icon's intent.
   */
  'aria-label'?: string;
}

function TonalIconBubbleImpl({
  tone,
  size = 'sm',
  tint,
  children,
  className = '',
  'aria-label': ariaLabel,
}: TonalIconBubbleProps) {
  const resolvedTint: TonalIconBubbleTint = tint ?? (size === 'xs' || size === 'sm' ? 'xs' : 'sm');
  const composed = [
    'rounded-full inline-flex items-center justify-center',
    SIZE_CLASS[size],
    TINT_CLASS[tone][resolvedTint],
    className,
  ].filter(Boolean).join(' ');
  // when the caller supplies a label, the bubble is the
  // accessible name of an icon that conveys real meaning, so
  // `aria-hidden` MUST come off. Otherwise the bubble is decorative.
  if (ariaLabel) {
    return <span className={composed} role="img" aria-label={ariaLabel}>{children}</span>;
  }
  return <span className={composed} aria-hidden="true">{children}</span>;
}

// TonalIconBubble is a pure tone/size/icon visual primitive
// with no internal state; props are tone strings, size strings, and a
// (typically stable) icon ReactNode. Memoising lets callers re-render
// without forcing a bubble re-paint when props are referentially stable.
export const TonalIconBubble = memo(TonalIconBubbleImpl);
