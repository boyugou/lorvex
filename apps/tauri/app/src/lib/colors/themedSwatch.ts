/**
 * Theme-aware user-color swatch helper.
 *
 * Direct passthrough of a user-stored hex color as
 * `style={{ backgroundColor: color }}` can produce low-contrast results
 * against the active theme surface — low-saturation colors disappear into
 * Dark/Midnight backgrounds, while highly saturated colors are too loud
 * on Light. `themedSwatch` clamps the rendered color by mixing it with
 * `var(--color-surface-2)` in OKLCH space, so the perceived contrast stays
 * consistent across themes.
 *
 * The mix percentage is calibrated per mode:
 *
 * - `dot`    — small (≤ 0.625rem) round indicator. Higher user-color
 *              weight (85%) so the hue stays recognizable at tiny sizes.
 * - `tile`   — larger filled swatch (chip, calendar wash). Lower
 *              user-color weight (60%) so adjacent text stays legible.
 * - `border` — left/edge accent border. Same weight as `dot` (the border
 *              is read as a thin strip and benefits from higher saturation).
 *
 * `color` may be `null` (no user color set), in which case the helper
 * falls through to `var(--color-warning)` — matching the
 * `eventDotColor` / `eventColorStyles` fallback so unset-color rendering
 * stays in lockstep across views.
 */

export type ThemedSwatchMode = 'dot' | 'tile' | 'border';

const MIX_PERCENT: Record<ThemedSwatchMode, number> = {
  dot: 85,
  tile: 60,
  border: 85,
};

/**
 * Compute a CSS color expression for a user-color swatch, clamped against
 * the active theme's `--color-surface-2` token.
 *
 * Returns a `color-mix(in oklch, …)` string suitable for use as
 * `style={{ backgroundColor: themedSwatch(color, 'dot') }}` or
 * inside a border shorthand (`${themedSwatch(color, 'border')}`).
 *
 * When `color` is `null`, returns `var(--color-warning)` directly (no
 * mixing) — the warning token is already theme-tuned.
 */
export function themedSwatch(color: string | null | undefined, mode: ThemedSwatchMode): string {
  if (!color) {
    return 'var(--color-warning)';
  }
  const pct = MIX_PERCENT[mode];
  return `color-mix(in oklch, ${color} ${pct}%, var(--color-surface-2))`;
}
