import type { ButtonHTMLAttributes, ReactNode } from 'react';

import { useReducedMotion } from '@/lib/reducedMotion';

/*
 * `<TonalButton>` primitive.
 *
 * The "outlined tone-coloured action" recipe — at the default `md`
 * size:
 *
 *   text-xs px-2.5 py-1 rounded-r-control
 *   border border-{tone}/40 text-{tone}
 *   hover background using the tone tint-sm token
 *   transition-colors disabled:opacity-50 disabled:cursor-not-allowed
 *   focus-ring-soft-{tone}
 *
 * — was hand-rolled in 8+ places: DangerZonePanel ("Delete all data",
 * "Reset preferences"), TrashPanel ("Empty trash", "Delete forever"),
 * DeferredTaskRow ("Archive"), SectionOverdueAlertCard
 * ("Reschedule all"), ChangelogView ("Clear all"), MemoryEntryCard
 * ("Forget"). Each one drifted in subtle ways (border opacity 25/30/40,
 * px-2.5 vs px-3, focus-ring soft vs soft-danger / soft-warning).
 * Pulling the recipe into a per-tone primitive collapses the drift the
 * same way Banner + chip-{tone} did for tonal panels and chips. The
 * focus ring is the per-tone variant `focus-ring-soft-{success,
 * warning, danger}` so the ring colour matches the button
 * tone instead of always landing on accent.
 *
 * Tone semantics mirror Banner / chip-{tone}:
 *   - `danger`   → destructive ("Delete", "Empty trash")
 *   - `warning`  → corrective ("Reset preferences", "Skip update")
 *   - `success`  → confirming ("Restore from backup")
 *   - `accent`   → emphasized affordance whose visual weight should
 *                  read as "first-class CTA in this row" without
 *                  promoting all the way to a `<Button variant='primary'>`.
 *                  Note: accent is the only tone that carries a
 *                  baseline tonal fill at rest (`--accent-tint-xs` —
 *                  see TONE_CLASS recipe). The danger / warning /
 *                  success tones are deliberately fill-less at rest
 *                  because their semantic colour already communicates
 *                  enough emphasis; accent's neutral hue needs the
 *                  extra fill rung to compete with surrounding chrome.
 * ( — McpSetupSection copy-snippet chips). Pairs
 *                  with the canonical `focus-ring-soft` (the default
 *                  accent ring) since no `focus-ring-soft-accent`
 *                  utility is needed — `focus-ring-soft` is already
 *                  accent-tinted.
 *
 * Distinct from `<Button variant='primary'>`:
 *                  Button.primary is a filled solid-accent CTA with
 *                  white text and a tooltip shadow — it dominates
 *                  the surface. TonalButton.accent is an inline
 *                  tonal chip (`accent-tint-xs` resting fill, accent
 * border, accent text —.) that reads as
 *                  emphasized in a dense action row but does not
 *                  take over the layout. Choose Button.primary when
 *                  the action is THE action on the surface; choose
 *                  TonalButton tone='accent' when it sits inline
 *                  alongside neutral / outline siblings.
 *
 * Pair with `size`:
 *   - `sm` → `text-2xs px-2 py-1` (sub-row actions, dense lists)
 *   - `md` → `text-xs px-2.5 py-1` (default — list rows)
 *   - `lg` → `text-xs px-3 py-1.5` (panel-level actions, danger-zone)
 */

type TonalButtonTone = 'danger' | 'warning' | 'success' | 'accent';
type TonalButtonSize = 'sm' | 'md' | 'lg';
/**
 * `fill` — visual weight modifier:
 *   - `outline` (default) → bordered chip with tonal text and (for
 *     accent only) a baseline tone tint-xs fill. The canonical
 *     `<TonalButton>` recipe documented above.
 *   - `soft` → borderless tonal chip with a tone tint-sm resting
 *     fill stepping up to tone tint-md on hover. Used by save /
 *     submit / start affordances inside dense panels (HabitReminders
 *     "Save", AddMemoryForm submit, today-view start-focus chip) where
 *     the bordered treatment reads as too heavy. The fill ladder is
 *     two rungs brighter than the outline accent's baseline so the
 *     soft chip reads as the more emphasized affordance — the
 *     border-vs-no-border axis is the visual signal here, not the
 *     fill saturation alone.
 */
type TonalButtonFill = 'outline' | 'soft';

const TONE_CLASS: Record<TonalButtonTone, string> = {
  danger: 'border border-danger/40 text-danger hover:bg-[var(--danger-tint-sm)] focus-ring-soft-danger',
  warning: 'border border-warning/40 text-warning hover:bg-[var(--warning-tint-sm)] focus-ring-soft-warning',
  success: 'border border-success/40 text-success hover:bg-[var(--success-tint-sm)] focus-ring-soft-success',
  // accent tone gets a baseline `accent-tint-xs` fill (the
  // tint rung one step below the hover `accent-tint-sm`) so the chip
  // reads as an emphasized affordance even at rest. This restores the
  // visual weight that the outline-only treatment lost. The
  // danger / warning / success tones intentionally remain fill-less at
  // rest: their tonal colour already carries enough emphasis (red,
  // amber, green read as semantic-heavy on their own), and adding a
  // baseline tint there would shout "destructive" / "warning" before
  // the user has invoked the action. Accent is the only tone that
  // needs the extra fill to compete with neutral chrome.
  accent: 'bg-[var(--accent-tint-xs)] border border-accent/40 text-accent hover:bg-[var(--accent-tint-sm)] focus-ring-soft',
};

// soft fill: borderless tonal chip with a brighter baseline.
// The hover steps up one tint rung so the affordance still reads as
// interactive without a border-color hover wash.
const TONE_CLASS_SOFT: Record<TonalButtonTone, string> = {
  danger: 'bg-[var(--danger-tint-sm)] text-danger hover:bg-[var(--danger-tint-md)] focus-ring-soft-danger',
  warning: 'bg-[var(--warning-tint-sm)] text-warning hover:bg-[var(--warning-tint-md)] focus-ring-soft-warning',
  success: 'bg-[var(--success-tint-sm)] text-success hover:bg-[var(--success-tint-md)] focus-ring-soft-success',
  accent: 'bg-[var(--accent-tint-sm)] text-accent hover:bg-[var(--accent-tint-md)] focus-ring-soft',
};

const SIZE_CLASS: Record<TonalButtonSize, string> = {
  sm: 'text-2xs px-2 py-1',
  md: 'text-xs px-2.5 py-1',
  lg: 'text-xs px-3 py-1.5',
};

export interface TonalButtonProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'type'> {
  tone: TonalButtonTone;
  size?: TonalButtonSize;
  /**
   * Visual weight modifier — see `TonalButtonFill`. Default `'outline'`.
   */
  fill?: TonalButtonFill;
  /**
   * In-flight indicator. When `true` the button:
   *   - is disabled,
   *   - announces `aria-busy="true"`,
   *   - prefixes the label with a small inline spinner (suppressed
   *     under `prefers-reduced-motion: reduce` per the SubmitButton
   *     pattern).
   *
   * Pass `loading={isPending}` from TanStack mutations.
   */
  loading?: boolean;
  children: ReactNode;
}

export function TonalButton({
  tone,
  size = 'md',
  fill = 'outline',
  loading = false,
  disabled,
  className = '',
  children,
  ...rest
}: TonalButtonProps) {
  const reducedMotion = useReducedMotion();
  const toneClass = fill === 'soft' ? TONE_CLASS_SOFT[tone] : TONE_CLASS[tone];
  const composed = [
    'rounded-r-control transition-colors disabled:opacity-50 disabled:cursor-not-allowed shrink-0 inline-flex items-center justify-center gap-1.5',
    SIZE_CLASS[size],
    toneClass,
    className,
  ].filter(Boolean).join(' ');
  return (
    <button
      type="button"
      className={composed}
      disabled={disabled || loading}
      aria-busy={loading || undefined}
      data-loading={loading || undefined}
      {...rest}
    >
      {loading && <TonalSpinner reducedMotion={reducedMotion} />}
      {/* Only wrap children in a span when the loading state needs to
          dim them — avoids a meaningless wrapper element on the steady
          state. (#3828) */}
      {loading ? <span className="opacity-90">{children}</span> : children}
    </button>
  );
}

function TonalSpinner({ reducedMotion }: { reducedMotion: boolean }) {
  // Mirrors `<SubmitButton>`'s spinner — 12px ring + arc; static under
  // reduced-motion (parent's aria-busy still announces in-flight).
  return (
    <svg
      aria-hidden="true"
      width="12"
      height="12"
      viewBox="0 0 24 24"
      fill="none"
      className={reducedMotion ? '' : 'animate-spin'}
    >
      <circle cx="12" cy="12" r="9" stroke="currentColor" strokeOpacity="0.25" strokeWidth="3" />
      <path d="M21 12a9 9 0 0 0-9-9" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
    </svg>
  );
}
