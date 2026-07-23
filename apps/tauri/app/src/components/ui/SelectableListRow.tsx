import { forwardRef, type ButtonHTMLAttributes, type ReactNode } from 'react';

/**
 * `<SelectableListRow>` primitive.
 *
 * The "selectable row inside a popover / picker / dropdown list" recipe
 * — a full-width button that renders a tone-tinted selected fill on
 * top of an accent-text foreground. , every picker overlay
 * (DueDate, List, Recurrence, Duration), CommandPalette, and a handful
 * of dropdown menus rolled the same recipe inline:
 *
 *   w-full flex items-center gap-2 px-2.5 py-1.5
 *   rounded-r-control text-sm transition-colors
 *   {selected ? 'bg-accent/15 text-accent' : 'text-text-primary hover:bg-surface-2/60'}
 *
 * with subtle drift on the selected fill (`/15` vs `/12` vs `/20`),
 * the idle hover (`hover:bg-surface-2/60` vs `hover:bg-surface-3/60`),
 * and the size (text-sm vs text-xs). The primitive pins the recipe to
 * the canonical `--{tone}-tint-sm` (`/20`) ladder rung and exposes a
 * `tone` axis matching Banner / Pill / TonalButton / ToggleChip.
 *
 * `size`:
 *   - `sm` → `text-xs px-2.5 py-1.5` (compact dropdown rows —
 *            PriorityDropdown, TimeHorizonPicker, SettingsScopeTabs)
 *   - `md` → `text-sm px-2.5 py-1.5` (default — picker overlays,
 *            CommandPalette)
 *
 * The component is a `<button>` so it stays keyboard-accessible without
 * extra wiring. Callers that need `role='option'` (CommandPalette
 * listbox) can pass it through via `...rest`.
 */

type SelectableListRowTone = 'accent';
type SelectableListRowSize = 'sm' | 'md';

const TONE_SELECTED: Record<SelectableListRowTone, string> = {
  accent: 'bg-[var(--accent-tint-sm)] text-accent',
};

const SIZE_CLASS: Record<SelectableListRowSize, string> = {
  sm: 'text-xs px-2.5 py-1.5',
  md: 'text-sm px-2.5 py-1.5',
};

const BASE =
  'w-full flex items-center gap-2 text-start rounded-r-control ' +
  'transition-colors focus-ring-soft active:scale-[0.99]';

const IDLE = 'text-text-primary hover:bg-surface-2/60';

interface SelectableListRowProps
  extends Omit<ButtonHTMLAttributes<HTMLButtonElement>, 'children'> {
  tone?: SelectableListRowTone;
  size?: SelectableListRowSize;
  selected?: boolean;
  /**
   * Override the selected-state classes. Used when the picker keys the
   * "selected" state off two axes (e.g. focus-highlight vs current
   * value) and wants different fills per axis.
   */
  selectedClassName?: string;
  children: ReactNode;
}

export const SelectableListRow = forwardRef<HTMLButtonElement, SelectableListRowProps>(
  function SelectableListRow(
    {
      tone = 'accent',
      size = 'md',
      selected = false,
      selectedClassName,
      className = '',
      type = 'button',
      children,
      ...rest
    },
    ref,
  ) {
    const stateClass = selected ? selectedClassName ?? TONE_SELECTED[tone] : IDLE;
    return (
      <button
        ref={ref}
        // eslint-disable-next-line react/button-has-type
        type={type}
        className={`${BASE} ${SIZE_CLASS[size]} ${stateClass} ${className}`.trim()}
        {...rest}
      >
        {children}
      </button>
    );
  },
);
