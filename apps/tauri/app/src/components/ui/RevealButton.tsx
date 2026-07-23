/**
 * RevealButton primitive.
 *
 * Generic counterpart to the chip-X primitive in `metadata-editor/
 * primitives.tsx`. Replaces six+ ad-hoc Tailwind reveal patterns
 * (`opacity-0 group-hover:opacity-100 group-focus-within:opacity-100`)
 * that all shared the same two latent defects:
 *
 *   1. **Touch-unreachable.** None of the legacy sites carried an
 *      `@media (hover: none)` always-on fallback, so on touch devices
 * the buttons were impossible to discover or invoke.
 *   2. **Sub-WCAG hit targets.** The `×`-glyph variants collapsed to
 *      ~16×20 pointer targets, well under the 24×24 minimum from
 * WCAG 2.5.8 Target Size.
 *
 * Both defects are now solved by CSS that lives next to
 * `.tag-x-button` in `index.css`:
 *   - `.reveal-on-hover` carries the opacity transition + the
 *     `@media (hover: none)` always-on fallback.
 *   - `.reveal-button-hit` carries a 24×24 `::before` focus-outline
 *     overlay (constant size, transform-centred) plus
 *     `min-width: 24px; min-height: 24px` so the button itself
 *     meets WCAG 2.5.8 independent of the visible icon size.
 *
 * The host of the button must carry the Tailwind `group` class so
 * the reveal can read the parent's hover / focus-within state.
 *
 * For non-button containers (e.g., a div wrapping multiple controls
 * that should reveal as a group), apply the `.reveal-on-hover` CSS
 * class directly. The same group/hover/focus-within/@media (hover:
 * none) contract applies, including the self-hover-to-1.0
 * escalation. The button-only ergonomics (24×24 hit overlay, tone
 * map, `<button type='button'>` defaults) live on this primitive
 * and are not needed for plain wrappers.
 *
 * The chip-X tag-removal button is intentionally NOT migrated to
 * this primitive — its slot-collapse uses a width animation
 * (`width 0 ↔ 0.875rem`) rather than a pure opacity reveal, and
 * the chip body owns the `group/tag` named scope. The
 * `.tag-x-button` shape keeps that geometry under its own
 * dedicated CSS arms; the shared `:where(.tag-x-button,
 * .reveal-button-hit)::before` base rule in `index.css` keeps the
 * 24×24 overlay geometry in lockstep across both primitives
 *.
 */
import type { ButtonHTMLAttributes, CSSProperties, ReactNode } from 'react';

/**
 * Helper for the `--reveal-opacity` custom property.
 *
 * The reveal-on-hover CSS reads `--reveal-opacity` to decide the
 * row-hover / focus-within base reveal opacity (default `1`). For
 * sites that want a soft 0 → 0.6 reveal with self-hover escalating
 * to 1.0, pass `style={revealOpacityStyle(0.6)}`.
 *
 * The helper exists so call sites don't have to repeat the
 * `['--reveal-opacity' as string]` cast every time — TypeScript's
 * `CSSProperties` doesn't accept arbitrary `--*` keys.
 */
export const revealOpacityStyle = (v: number): CSSProperties =>
  ({ ['--reveal-opacity' as string]: String(v) }) as CSSProperties;

/** Color tone for the icon. Maps to base + hover Tailwind colour pairs. */
type RevealButtonTone =
  /** Muted text → danger on hover. The default for ×/trash/unlink. */
  | 'danger'
  /** Muted text → primary text on hover. Neutral, non-destructive. */
  | 'neutral'
  /** Muted text → accent on hover. For positive affordances (copy id). */
  | 'accent'
  /** Muted text → muted text + subtle surface tint on hover. For
   *  reorder / nudge controls that shouldn't shift colour but want a
   * background-flash hover affordance. */
  | 'subtle';

const TONE_CLASSES: Record<RevealButtonTone, string> = {
  danger: 'text-text-muted hover:text-danger',
  neutral: 'text-text-muted hover:text-text-primary',
  accent: 'text-text-muted hover:text-accent',
  subtle: 'text-text-muted hover:bg-[var(--color-hover-tint)]',
};

/** Visual size variant. Affects padding only; the WCAG 24×24 hit
 *  area is enforced by `.reveal-button-hit` when `hitTarget=true`.
 *  With `hitTarget=false` the caller is responsible for meeting
 * the 24×24 minimum on its own. */
type RevealButtonSize =
  /** No padding — caller fully controls box size. The default. */
  | 'compact'
  /** Menu-row padding (`px-1.5 py-1`) — for buttons that sit inside
   *  list rows where the visible button needs a comfortable gap
   * between the glyph and the row chrome. */
  | 'comfortable';

const SIZE_CLASSES: Record<RevealButtonSize, string> = {
  compact: '',
  comfortable: 'px-1.5 py-1',
};

export interface RevealButtonProps
  extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'children' | 'aria-label' | 'type'> {
  /** Icon (or text) shown inside the button. */
  children: ReactNode;
  /** Required accessible name — the visible glyph is hidden from AT. */
  'aria-label': string;
  /** Colour tone (default: `'danger'`). */
  tone?: RevealButtonTone;
  /** When true (default), attach the WCAG 2.5.8 24×24 contract via
   *  the `.reveal-button-hit` class — `min-width: 24px;
   *  min-height: 24px` on the button itself plus a `::before`
   *  focus-outline overlay sized to a constant 24×24 box invariant
   *  to the button's animating padding. Set to `false` for buttons
   *  that already meet the minimum by virtue of their own padding
   *  / typography (e.g. the TaskDetailHeader copy-id button, which
   *  reads as a long monospace string). The focus-visible outline
   *  rule still applies via `.reveal-button-no-hit:focus-visible`
   * (,). */
  hitTarget?: boolean;
  /** Visual size variant (default: `'compact'`). See `RevealButtonSize`. */
  size?: RevealButtonSize;
  /** Optional extra class names appended to the button. Use for
   *  layout-only adjustments (padding, font-size, border-radius).
   *  For end-state opacity != 1, pass
   *  `style={revealOpacityStyle(0.6)}` (or any other value) — the
   *  primitive intentionally does not own a numeric prop for this
   * (,). */
  className?: string;
}

/**
 * Reveal-on-hover button with built-in touch fallback and a
 * 24×24 hit-target contract (WCAG 2.5.8). The host must carry the
 * `group` class so hover / focus-within propagates.
 */
export function RevealButton({
  children,
  tone = 'danger',
  hitTarget = true,
  size = 'compact',
  className,
  ...rest
}: RevealButtonProps) {
  const classes = [
    'reveal-on-hover',
    hitTarget ? 'reveal-button-hit' : 'reveal-button-no-hit',
    TONE_CLASSES[tone],
    SIZE_CLASSES[size],
    'rounded-r-control',
    // The hit-target overlay carries focus-visible when `hitTarget`
    // is true (`.reveal-button-hit:focus-visible::before`); when
    // it's off, `.reveal-button-no-hit:focus-visible` carries an
    // identical outline directly on the button. Either way we
    // suppress the UA default outline since the explicit rule
    // takes over.
    'focus-visible:outline-hidden',
    // motion-reduce:transition-none is unnecessary here —
    // the global `@media (prefers-reduced-motion: reduce)` rule in
    // index.css clamps every transition-duration to 0.01ms.
    'transition-colors',
    className,
  ]
    .filter(Boolean)
    .join(' ');

  return (
    <button type="button" className={classes} {...rest}>
      {children}
    </button>
  );
}
