import { themedSwatch } from './colors/themedSwatch';

/**
 * Append a hex alpha channel to a color string.
 * Normalizes 3-digit hex (#RGB) to 6-digit (#RRGGBB) before appending,
 * so the result is always a valid 8-digit hex color (#RRGGBBAA).
 *
 * If the input is not a hex color, returns it unchanged (no alpha appended).
 *
 * Non-hex input is returned unchanged. Keep this helper side-effect-free:
 * production console output is reserved for the client-error-log fallback.
 */

export function hexWithAlpha(hex: string, alphaHex: string): string {
  if (!hex.startsWith('#')) {
    return hex;
  }
  const body = hex.slice(1);
  if (!/^[0-9a-fA-F]+$/.test(body)) return hex;

  if (body.length === 3 || body.length === 4) {
    const expanded = Array.from(body.slice(0, 3), (char) => char + char).join('');
    return `#${expanded}${alphaHex}`;
  }

  if (body.length === 6 || body.length === 8) {
    return `#${body.slice(0, 6)}${alphaHex}`;
  }

  return hex;
}

// ---------------------------------------------------------------------------
// Event-color helper
// ---------------------------------------------------------------------------

/**
 * Strength tier for `eventColorStyles`. Maps to a fixed (background,
 * border-mix) alpha pair so the calendar/upcoming/today/popover rows
 * read as the same visual language across views.
 *
 * - `soft`   — subtle wash for dense surfaces (week timeline, month
 *              pills, popover lists)
 * - `medium` — default tier for event chips and day-panel rows
 * - `strong` — emphasized tier (selected event, focused link list)
 */
export type EventColorIntensity = 'soft' | 'medium' | 'strong';

interface EventColorStyle {
  backgroundColor: string;
  borderInlineStart: string;
}

const INTENSITY_BG_ALPHA: Record<EventColorIntensity, number> = {
  soft: 0.10,
  medium: 0.15,
  strong: 0.22,
};

/**
 * Build a `{ backgroundColor, borderInlineStart }` style pair for an event whose
 * primary color may be either a hex string from the user-managed
 * calendar palette or `null` (fall back to `--color-warning`).
 *
 * The background is computed via OKLCH alpha mixing
 * (`oklch(from <color> l c h / α)`) so the same input hex lands at
 * perceptually-uniform luminance regardless of the active theme.
 * `null` falls through to a `color-mix(in oklch, var(--color-warning) …)`
 * tinted variant so the warning hue stays in lockstep with theme
 * retunes. The inline-start border always renders the source color at full
 * opacity — either the event's own hex or the warning token.
 */
/**
 * Solid color value for a small event indicator (e.g. a dot or a
 * 1.5×1.5 chip in dense lists). `null` falls through to
 * `var(--color-warning)` so the unset-color fallback stays in lockstep
 * with the chip background — which uses a warning-tinted wash.
 *
 * Routed through `themedSwatch(color, 'dot')` so user-stored
 * colors are contrast-clamped against the active theme surface. Saturated
 * picks no longer dominate Light surfaces; low-saturation picks stay
 * visible on Dark/Midnight.
 */
export function eventDotColor(color: string | null): string {
  return themedSwatch(color, 'dot');
}

export function eventColorStyles(
  color: string | null,
  intensity: EventColorIntensity = 'medium',
  borderWidth: number = 3,
): EventColorStyle {
  const alpha = INTENSITY_BG_ALPHA[intensity];
  if (!color) {
    return {
      backgroundColor: `color-mix(in oklch, var(--color-warning) ${Math.round(alpha * 100)}%, transparent)`,
      borderInlineStart: `${borderWidth}px solid var(--color-warning)`,
    };
  }
  return {
    backgroundColor: `oklch(from ${color} l c h / ${alpha})`,
    borderInlineStart: `${borderWidth}px solid ${themedSwatch(color, 'border')}`,
  };
}
