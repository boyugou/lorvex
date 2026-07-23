/**
 * `<ToggleChip>` primitive (promoted from
 * `quick-capture/ToolbarChip` to a shared `ui/` primitive).
 *
 * Canonical "selectable accent chip" recipe — the small pill button
 * that renders an idle / selected pair across the app: quick-capture
 * toolbar (DatePills, DurationDropdown, PriorityDropdown, TagsToggle),
 * changelog filter chips, calendar view-mode segmented control,
 * mobile list filter row, settings segmented controls (week start,
 * focus break), DatePicker quick-chips, and the focus-popover
 * pause/resume pill.
 *
 * , every site rebuilt the same recipe by hand and drifted on
 * three axes:
 *   - selected fill — `bg-accent/15`, `bg-accent/20`, `bg-accent/12`
 *     (off-ladder); only `accent-tint-sm` (`/20`) is on the canonical
 *     accent-tint ladder. ToggleChip pins the selected state to the
 *     `/20` rung so the visual emphasis is consistent across surfaces.
 *   - size — `text-xs px-2 py-1`, `text-xs px-2.5 py-1`,
 *     `text-sm px-3 py-1.5`. ToggleChip exposes three rungs (`xs`,
 *     `sm`, `md`) covering every existing call site.
 *   - idle hover — sometimes `hover:bg-surface-3`, sometimes
 *     `hover:text-text-primary`, sometimes both. ToggleChip picks the
 *     ergonomic default (text-secondary on hover + surface-3 wash) and
 *     lets callers override via `inactiveClassName` when a segmented
 *     control needs a fill-only treatment without the hover wash.
 *
 * `tone` widens the colour axis to the canonical four-rung ladder
 * (: `accent | warning | danger | success`) so tonal segmented
 * controls (e.g. a danger-tinted filter) can land without renaming the
 * API. Each tone resolves to its `--{tone}-tint-sm` rung — the same
 * `/20` step the accent ladder pins — so all four read at consistent
 * visual weight when selected.
 *
 * `variant='segmented'` bakes the no-bg-wash idle state used
 * inside bordered segmented groups (calendar view-mode, week-start
 * day picker, focus-break option picker). The chip drops the
 * `hover:bg-surface-3` wash and rounds to the group's outer radius so
 * the inner buttons share corners cleanly.
 *
 * `shape='pill'` overrides the default control radius with
 * `rounded-full`, used by the focus-popover pause/resume affordance
 * which carries a heftier capsule rhythm. Default `'control'` matches
 * the canonical `--radius-r-control` token.
 */
import { forwardRef, type ReactNode, type ButtonHTMLAttributes } from 'react';

// all type aliases are internal: the JSX call sites pass
// string literals directly so no external module ever imports these
// names. Keeping them un-exported avoids stale public-surface entries
// that drift on every primitive retune.
type ToggleChipTone = 'accent' | 'warning' | 'danger' | 'success';
type ToggleChipSize = 'xs' | 'sm' | 'md';
type ToggleChipVariant = 'default' | 'segmented';
type ToggleChipShape = 'control' | 'pill';

const SIZE_CLASS: Record<ToggleChipSize, string> = {
  // Filter pill (changelog op / entity filters): `text-xs px-2 py-0.5`
  // is the smallest rung.
  xs: 'text-xs px-2 py-0.5',
  // Default — the quick-capture toolbar rhythm and the calendar /
  // weekly-review / DatePicker quick-chip rhythm.
  sm: 'text-xs px-2 py-1',
  // Settings segmented controls (week-start day picker, focus-break
  // option picker) carry a heftier rhythm to match the `text-sm`
  // body type of the surrounding settings panel.
  md: 'text-sm px-3 py-1.5',
};

// Selected fills pin to each tone's canonical `--{tone}-tint-sm`
// (the /20 rung). Off-ladder alphas (`/12`, `/15`) are intentionally
// not exposed — see file-level doc.
const SELECTED_CLASS: Record<ToggleChipTone, string> = {
  accent: 'bg-[var(--accent-tint-sm)] text-accent',
  warning: 'bg-[var(--warning-tint-sm)] text-warning',
  danger: 'bg-[var(--danger-tint-sm)] text-danger',
  success: 'bg-[var(--success-tint-sm)] text-success',
};

const IDLE_DEFAULT = 'text-text-muted hover:text-text-secondary hover:bg-surface-3';
// `segmented` idle drops the surface-wash so inner buttons inside a
// bordered segmented group share the group's flat resting state.
const IDLE_SEGMENTED = 'text-text-muted hover:text-text-primary';

const SHAPE_CLASS: Record<ToggleChipShape, string> = {
  control: 'rounded-r-control',
  pill: 'rounded-full',
};

// xs uses pill shape by default — the `0.5` vertical padding makes
// the control radius (4px) read as a near-square chip, so the
// canonical xs rung is a capsule unless the caller overrides via
// `shape='control'`.
const XS_DEFAULT_SHAPE: ToggleChipShape = 'pill';

const BASE_CLASSES =
  'inline-flex items-center gap-1 transition-colors active:scale-[0.97] focus-ring-soft';

interface ToggleChipProps extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'children'> {
  /** Visual emphasis. Default `'accent'`. */
  tone?: ToggleChipTone;
  /**
   * Whether the chip is in its selected (filled) state. The caller
   * owns the binding (controlled component); the chip renders the
   * matching tone fill when `true`.
   */
  selected?: boolean;
  /** Size rung. Default `'sm'`. */
  size?: ToggleChipSize;
  /**
   * Visual variant. `'default'` carries the `hover:bg-surface-3`
   * wash; `'segmented'` drops the wash and the chip's own
   * radius so it can sit inside a bordered segmented group cleanly.
   */
  variant?: ToggleChipVariant;
  /**
   * Corner shape. `'control'` (default) → `--radius-r-control`;
   * `'pill'` → `rounded-full` for capsule affordances like
   * the focus-popover pause/resume chip. `xs` defaults to `'pill'`
   * regardless of this prop unless overridden.
   */
  shape?: ToggleChipShape;
  /**
   * Override the selected-state classes. Used by `PriorityDropdown`
   * to tint the chip with the priority colour and by
   * `DurationDropdown` to route through a danger ring on validation
   * failure. When set, `tone` is ignored for the selected state.
   */
  selectedClassName?: string | undefined;
  /**
   * Override idle (unselected) classes when a caller needs a
   * different idle treatment beyond what `variant` covers — e.g.
   * the focus-popover "running" state which uses a custom
   * `bg-surface-2/60` resting fill.
   */
  inactiveClassName?: string | undefined;
  children: ReactNode;
}

/**
 * Selectable accent chip — see file-level doc for the canonical
 * recipe. Caller controls `selected`; primitive owns size, focus
 * ring, transition, and active-press scale.
 */
export const ToggleChip = forwardRef<HTMLButtonElement, ToggleChipProps>(function ToggleChip({
  tone = 'accent',
  selected = false,
  size = 'sm',
  variant = 'default',
  shape,
  selectedClassName,
  inactiveClassName,
  className = '',
  type = 'button',
  children,
  ...rest
}, ref) {
  const hasExplicitSelectionState =
    rest['aria-pressed'] !== undefined ||
    rest['aria-selected'] !== undefined ||
    rest['aria-checked'] !== undefined;
  const defaultSelectionState = hasExplicitSelectionState ? {} : { 'aria-pressed': selected };
  const idleClass = variant === 'segmented' ? IDLE_SEGMENTED : IDLE_DEFAULT;
  const stateClass = selected
    ? selectedClassName ?? SELECTED_CLASS[tone]
    : inactiveClassName ?? idleClass;
  // Segmented variant drops its own radius so the bordered group's
  // outer radius governs corner shape; otherwise honour `shape` (or
  // the xs default capsule).
  const shapeClass =
    variant === 'segmented'
      ? 'rounded-none'
      : SHAPE_CLASS[shape ?? (size === 'xs' ? XS_DEFAULT_SHAPE : 'control')];
  return (
    <button
      ref={ref}
      // Wrapper component forwards a defaulted `type` prop ('button');
      // the rule wants a static string but the wrapper guarantees a
      // safe default while still allowing callers to opt into 'submit'.
      // eslint-disable-next-line react/button-has-type
      type={type}
      className={`${BASE_CLASSES} ${SIZE_CLASS[size]} ${shapeClass} ${stateClass} ${className}`.trim()}
      {...defaultSelectionState}
      {...rest}
    >
      {children}
    </button>
  );
});
