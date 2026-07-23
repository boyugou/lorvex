import { memo, type HTMLAttributes, type ReactNode } from 'react';

/*
 * `<Pill>` primitive.
 *
 * The "rounded-full tonal badge" recipe — small status / count
 * affordances rendered as a fully-rounded capsule rather than the
 * `chip-tight` square-rounded chip — was hand-rolled across the
 * popover badges (now / overdue / next-up counts), the sidebar
 * notifications-blocked indicator, the upcoming-view week pill, and
 * other status capsules. Each call site reinvented the same recipe
 * with subtle drift (px-1.5 vs px-2, py-0 vs py-0.5, font-medium vs
 * font-semibold). The primitive consolidates the recipe so the next
 * time we want to retune pill rhythm we change one place.
 *
 * Tones map to the same ladder as `<Banner>` / `<TonalButton>` /
 * `chip-{tone}`:
 *   - `success`  → `chip-success`  (success-tint-sm + text-success)
 *   - `warning`  → `chip-warning`
 *   - `danger`   → `chip-danger`
 *   - `accent`   → faint accent fill (matches popover accent badges)
 *   - `muted`    → surface-2 fill, muted text (default)
 *
 * Sizing pairs:
 *   - `sm` → `text-3xs px-1.5 py-px`   (popover row badges)
 *   - `md` → `text-2xs px-2 py-0.5`    (sidebar / general status)
 *   - `lg` → `text-xs  px-2.5 py-0.5`  (panel-level status)
 *
 * `tabular` adds `tabular-nums font-semibold` for count badges where
 * digit width parity matters (overdue-count, due-soon-count). Without
 * `tabular`, `font-medium` keeps the typography quieter.
 */

export type PillTone = 'success' | 'warning' | 'danger' | 'accent' | 'muted';
type PillSize = 'sm' | 'md' | 'lg' | 'cozy';

const TONE_CLASS: Record<PillTone, string> = {
  success: 'chip-success',
  warning: 'chip-warning',
  danger: 'chip-danger',
  accent: 'bg-accent/10 text-accent',
  muted: 'bg-surface-2/60 text-text-muted/80',
};

// radius is encoded per size, not in the base, so callers can
// pick chip vs. capsule shape without relying on later-wins class-order
// behavior. The capsule sizes (`sm`/`md`/`lg`) carry `rounded-full`;
// the chip-shaped `cozy` carries the chip-radius token.
const SIZE_CLASS: Record<PillSize, string> = {
  sm: 'rounded-full text-3xs px-1.5 py-px',
  md: 'rounded-full text-2xs px-2 py-0.5',
  lg: 'rounded-full text-xs px-2.5 py-0.5',
  // `cozy` is the chip-shape variant introduced for the TodayHeader
  // overdue/today-pool count chips. It uses the chip radius
  // (`--radius-r-chip`) rather than the default capsule and a slightly
  // taller `py-1` rhythm so the chip reads as a panel-level status badge
  // rather than a tight popover capsule.
  cozy: 'rounded-r-chip text-xs px-2.5 py-1',
};

interface PillProps extends HTMLAttributes<HTMLSpanElement> {
  tone?: PillTone;
  size?: PillSize;
  /** Render with `tabular-nums font-semibold` for count badges. */
  tabular?: boolean;
  children: ReactNode;
}

function PillImpl({
  tone = 'muted',
  size = 'md',
  tabular = false,
  className = '',
  children,
  ...rest
}: PillProps) {
  const composed = [
    'inline-flex items-center gap-1 leading-none whitespace-nowrap',
    SIZE_CLASS[size],
    TONE_CLASS[tone],
    tabular ? 'tabular-nums font-semibold' : 'font-medium',
    className,
  ].filter(Boolean).join(' ');
  return (
    <span className={composed} {...rest}>
      {children}
    </span>
  );
}

// Pill is a pure rendering primitive: tone/size/tabular are
// strings/booleans, the children are typically a count or label
// string, and the spread props are mostly stable a11y attributes.
// Memoising lets parent re-renders skip the bubble paint when props
// are referentially stable.
export const Pill = memo(PillImpl);
