import type { CSSProperties } from 'react';

/*
 * focus-mode background gradient extraction.
 *
 * Both the focus-mode empty state and the focus-mode active state
 * compose the same three-stop linear gradient — `surface-1` at the top
 * fading through `surface-0` to a slightly weaker `surface-0` at the
 * bottom, each stop scaled by the user's chosen window opacity. The
 * recipe was hand-coded inline in two places, so a future tweak to the
 * stop percentages or surface tokens would have had to be repeated in
 * lockstep. Centralising here keeps the two surfaces guaranteed-equal.
 *
 * Returns an empty `CSSProperties` object when `bgOpacity >= 1` so the
 * caller can spread it unconditionally without re-deriving the gating
 * branch on each render.
 */
export function focusModeBackground(bgOpacity: number): CSSProperties {
  if (bgOpacity >= 1) return {};
  const top = Math.round(bgOpacity * 95);
  const mid = Math.round(bgOpacity * 90);
  const bottom = Math.round(bgOpacity * 86);
  return {
    background: `linear-gradient(to bottom, color-mix(in oklch, var(--color-surface-1) ${top}%, transparent) 0%, color-mix(in oklch, var(--color-surface-0) ${mid}%, transparent) 70%, color-mix(in oklch, var(--color-surface-0) ${bottom}%, transparent) 100%)`,
  };
}
