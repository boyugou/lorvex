/**
 * Stable, deterministic colour palette for tag chips.
 *
 * Each tag name hashes to a fixed slot in `TAG_COLOR_PALETTE` so the
 * same tag string always renders with the same hue, regardless of where
 * the chip is shown or how the surrounding list is ordered. The palette
 * is intentionally small (8 hues) so colour repetition reads as
 * "another tag on the same theme" rather than as a collision bug.
 *
 * Extracted from `metadata-editor/primitives.tsx` so other tag
 * surfaces (filter pills, command palette, tag manager …) can share the
 * same hash without re-importing chip-rendering primitives.
 */

/** Tailwind class triplet for a tag chip — left border, soft fill, text. */
export interface TagColor {
  readonly border: string;
  readonly bg: string;
  readonly text: string;
}

const TAG_COLOR_PALETTE: readonly TagColor[] = [
  { border: 'border-s-accent',       bg: 'bg-accent/8',    text: 'text-accent' },
  { border: 'border-s-success',      bg: 'bg-[var(--success-tint-xs)]',   text: 'text-success' },
  { border: 'border-s-warning',      bg: 'bg-[var(--warning-tint-xs)]',   text: 'text-warning' },
  { border: 'border-s-danger',       bg: 'bg-[var(--danger-tint-xs)]',    text: 'text-danger' },
  // Additional hues via opacity blends — same families, lighter weight.
  { border: 'border-s-accent/70',    bg: 'bg-accent/6',    text: 'text-accent/80' },
  { border: 'border-s-success/70',   bg: 'bg-[var(--success-tint-xs)]',   text: 'text-success/80' },
  { border: 'border-s-warning/70',   bg: 'bg-[var(--warning-tint-xs)]',   text: 'text-warning/80' },
  { border: 'border-s-danger/70',    bg: 'bg-[var(--danger-tint-xs)]',    text: 'text-danger/80' },
] as const;

/** djb2-ish 32-bit hash of a tag name; folded to a non-negative magnitude.
 *
 * lowercase the input internally so callers don't have to. Tag
 * names are already canonicalised to lowercase on persistence (see
 * `TagsField.addTag` in `metadata-editor/primitives.tsx`), but this
 * function is also called against pre-canonical input from filter
 * pills / command-palette autocomplete where the casing is whatever
 * the user typed. Without this guard `Work` and `work` would land on
 * different palette slots for the same conceptual tag.
 *
 * cast the signed 32-bit hash to unsigned via `>>> 0` instead
 * of `Math.abs`. `Math.abs(-2147483648)` returns `2147483648` (one
 * past INT32_MAX), but the original bitwise hash can only reach that
 * value as a signed underflow — `Math.abs` papers over the wrap-
 * around with a value that's never actually a real hash output.
 * `>>> 0` is the canonical "reinterpret as uint32" idiom and gives a
 * uniform distribution across the palette modulus.
 */
function hashTagName(name: string): number {
  const lower = name.toLowerCase();
  let hash = 0;
  for (let i = 0; i < lower.length; i++) {
    hash = ((hash << 5) - hash + lower.charCodeAt(i)) | 0;
  }
  return hash >>> 0;
}

/** Resolve the palette slot for a tag name. Total over all strings. */
export function getTagColor(tag: string): TagColor {
  return TAG_COLOR_PALETTE[hashTagName(tag) % TAG_COLOR_PALETTE.length]!;
}
