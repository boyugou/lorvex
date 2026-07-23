/**
 * Quick-capture popover layering tokens.
 *
 * Quick-capture itself is a modal-class surface — every dropdown
 * (priority / duration / tags / due-date) anchors above it and must
 * stack above the modal layer to avoid getting clipped by the
 * quick-capture body. The shared z-class lifts all four popovers two
 * rungs above `--z-modal` so they sit on the same plane regardless of
 * mount order, and a single retune lands across every dropdown.
 *
 * Pair with `popover-shell` for the common chrome (border, radius,
 * surface, shadow) so a per-popover className only carries the
 * geometry + padding the popover itself needs.
 */
export const QUICK_CAPTURE_POPOVER_Z_CLASS = 'z-[calc(var(--z-modal)+2)]';

/**
 * Canonical popover-chrome bundle used by every quick-capture
 * dropdown. Carries the surface + popover border + radius + shadow +
 * fade-in entrance. Consumers append spacing (`p-1` / `p-2` / `py-1`)
 * and `fixed` / `absolute` positioning per their anchor strategy.
 */
export const QUICK_CAPTURE_POPOVER_SHELL_CLASS =
  'bg-surface-1 border border-popover rounded-r-panel shadow-[var(--shadow-popover)] animate-[fade-in_0.1s_ease-out]';
