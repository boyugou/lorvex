import type { ReactNode } from 'react';
import { Children, isValidElement } from 'react';

/*
 * `<Banner>` primitive.
 *
 * Lorvex grew ~12 hand-rolled tonal banners across the app: notification
 * permission, stale data, sync error / reseed / preflight
 * / circuit-broken / auto-paused, calendar offline empty state, recurrence
 * external-update, etc. Each one re-derived the same recipe —
 *
 *     border border-{tone}/30 plus the tone tint-sm background token
 *     rounded-r-card px-4 py-2 flex items-center
 *
 * — with subtle drift in radius, padding, role, and aria-live values
 * that the user could feel as visual noise but no one banner could fix
 * alone. The primitive consolidates the recipe so the next time we want
 * to retune banner padding or accessibility metadata, we change it in
 * one place and every banner moves together.
 *
 * Tone semantics mirror the toast taxonomy:
 *   - `info`     → neutral surface; non-actionable status
 *   - `success`  → positive confirmation (rarely used as a banner)
 *   - `warning`  → user should act, but the operation is not broken
 *   - `danger`   → error state, often blocking; uses role=alert by default
 *
 * The banner *intentionally* does not own its own dismiss button —
 * dismissal state is feature-specific (session-only vs persistent vs
 * none) and belongs to the caller. Pass a button into `actions` if a
 * dismiss control is part of the banner's affordance.
 */

type BannerTone = 'success' | 'warning' | 'danger' | 'info';

/**
 * Density controls vertical padding.
 *
 *   - `cozy`        → `py-2.5`
 *   - `comfortable` → `py-3` (default — the canonical banner padding;
 *                              matches every hand-rolled banner before
 *                              `<Banner>` collapsed them).
 */
type BannerDensity = 'cozy' | 'comfortable';

/**
 * Vertical alignment escape hatch.
 *
 * Default policy:
 *   - `center` if `title` is set OR body is single-line
 *     (single string with no newline, or single primitive child).
 *   - `start`  if no `title` AND body has multiple lines or wraps a
 *     multi-paragraph node.
 *
 * Override only when the heuristic disagrees with the visual result —
 * e.g. a no-title banner whose body deliberately wraps short.
 */
type BannerAlign = 'start' | 'center';

export interface BannerProps {
  tone: BannerTone;
  /** Optional bold heading. When omitted the banner is single-line. */
  title?: string;
  /** Body content; can be a string or rich nodes (e.g. inline links). */
  children: ReactNode;
  /** Right-aligned action slot — typically `<button>` elements. */
  actions?: ReactNode;
  /** Optional leading icon. Rendered without spacing if absent. */
  icon?: ReactNode;
  /** Override `role`. Defaults to `alert` for danger, `status` otherwise. */
  role?: 'alert' | 'status';
  /** Override `aria-live`. Defaults to `assertive` for danger, `polite` otherwise. */
  ariaLive?: 'assertive' | 'polite' | 'off';
  /** Body text colour. Defaults to `secondary` so the tonal title stays the dominant cue. */
  bodyTone?: 'primary' | 'secondary';
  /** Vertical padding density. Defaults to `comfortable`. */
  density?: BannerDensity;
  /**
   * Vertical alignment override. Defaults are derived from
   * `title` + body shape; pass explicitly when the heuristic is wrong.
   */
  align?: BannerAlign;
  /** Extra utility classes for layout-level concerns (margin, width, etc.). */
  className?: string;
}

const TONE_SHELL: Record<BannerTone, string> = {
  success: 'tonal-surface-success-sm',
  warning: 'tonal-surface-warning-sm',
  danger: 'tonal-surface-danger-sm',
  info: 'border-accent/20 bg-[var(--accent-tint-xs)]',
};

const DENSITY_CLASS: Record<BannerDensity, string> = {
  cozy: 'py-2.5',
  comfortable: 'py-3',
};

const TONE_TITLE: Record<BannerTone, string> = {
  success: 'text-success',
  warning: 'text-warning',
  danger: 'text-danger',
  info: 'text-text-primary',
};

/*
 * body-copy hierarchy. Every previous hand-rolled banner
 * rendered its body in `text-text-secondary` so the colored title +
 * tonal shell stayed the dominant visual cue. The early `Banner`
 * primitive promoted bodies to `text-text-primary`, which flattened
 * the hierarchy: a danger banner with a primary-coloured body fights
 * the danger title for attention. Default back to secondary; callers
 * with a single-line banner (no title) and a need to emphasise the
 * body can override via `bodyTone`.
 */
const TONE_BODY: Record<BannerTone, string> = {
  success: 'text-text-secondary',
  warning: 'text-text-secondary',
  danger: 'text-text-secondary',
  info: 'text-text-secondary',
};

const BODY_TONE_PRIMARY = 'text-text-primary';

/**
 * Heuristic: does the body look single-line?
 *
 * Used by the `align` default policy. A body is "single-line"
 * if it is a single string without newlines, or a single primitive
 * child. Multi-paragraph nodes (arrays, fragments, multi-newline
 * strings) default to `items-start` so the icon/title align to the
 * first cap-line.
 */
function bodyLooksSingleLine(children: ReactNode): boolean {
  if (typeof children === 'string') return !children.includes('\n');
  if (typeof children === 'number' || typeof children === 'boolean') return true;
  if (children == null) return true;
  if (Array.isArray(children)) {
    const arr = Children.toArray(children).filter(
      (c) => !(typeof c === 'string' && c.trim() === '')
    );
    if (arr.length > 1) return false;
    return arr.length === 1 ? bodyLooksSingleLine(arr[0] as ReactNode) : true;
  }
  if (isValidElement(children)) {
    // Rich element body — assume multi-line capable.
    return false;
  }
  return true;
}

export function Banner({
  tone,
  title,
  children,
  actions,
  icon,
  role,
  ariaLive,
  bodyTone,
  density = 'comfortable',
  align,
  className = '',
}: BannerProps) {
  const resolvedRole = role ?? (tone === 'danger' ? 'alert' : 'status');
  const resolvedAriaLive =
    ariaLive ?? (tone === 'danger' ? 'assertive' : 'polite');
  const shell = TONE_SHELL[tone];
  const titleClass = TONE_TITLE[tone];
  const bodyClass = bodyTone === 'primary' ? BODY_TONE_PRIMARY : TONE_BODY[tone];
  // alignment policy:
  //   - `center` when `title` is set (the title-first column sits
  //     centred against the icon/actions baseline) OR when the body
  // is a single line (legacy `items-center` behaviour ).
  //   - `start` only when there is no title AND the body is
  //     multi-line/rich, so the icon aligns with the body's first
  //     cap-line.
  // The `align` prop overrides the heuristic when needed.
  const resolvedAlign: BannerAlign =
    align ?? (title || bodyLooksSingleLine(children) ? 'center' : 'start');
  const verticalAlignment = resolvedAlign === 'start' ? 'items-start' : 'items-center';
  const densityClass = DENSITY_CLASS[density];

  return (
    <div
      role={resolvedRole}
      aria-live={resolvedAriaLive}
      className={[
        `rounded-r-card border px-4 ${densityClass} flex ${verticalAlignment} justify-between gap-3`,
        shell,
        className,
      ].filter(Boolean).join(' ')}
    >
      {icon && <span className={`shrink-0 ${resolvedAlign === 'start' ? 'mt-0.5' : ''}`}>{icon}</span>}
      <div className="flex-1 min-w-0 flex flex-col gap-0.5">
        {title && (
          <p className={`text-xs font-medium ${titleClass}`}>{title}</p>
        )}
        <div className={`text-xs leading-relaxed ${bodyClass}`}>{children}</div>
      </div>
      {actions && <div className="flex items-center gap-2 shrink-0">{actions}</div>}
    </div>
  );
}
