import { forwardRef } from 'react';

/**
 * `<CompactNumberInput>` primitive.
 *
 * Encodes the "tight numeric stepper inside a popover / chip toolbar"
 * recipe that the duration dropdown (`DurationDropdown.tsx`) hand-rolled
 * inline: a narrow, fixed-width `<input type="number">` that
 *   - opts into the validated-input affordance (`.validated-input`
 *     auto-applies the danger-tinted border + focus ring once the host
 *     sets `aria-invalid='true'`),
 *   - sits on a `bg-surface-3` chip background so it reads as nested
 *     inside its parent surface rather than competing with the popover
 *     fill,
 *   - hides the WebKit/Firefox spinner UI because the surrounding
 *     toolbar already has explicit increment chips, and a stepper
 *     widget inside a 56-px input cramps the digits, and
 *   - uses the soft focus-ring because the stepper is one of
 *     several controls in the toolbar — the strong ring would steal
 *     attention from the primary action.
 *
 * `RecurrenceField` migrated in once the `background` prop
 * existed; `EventRecurrenceFields` and `TaskUnifiedMetaCard` joined in
 * once the resting-border map made the recipe correct on
 * non-default surface tiers. If a future call site wants the same
 * chip-style stepper, route it through this primitive rather than
 * re-rolling the recipe inline.
 */

type CompactNumberInputBackground = 'surface-1' | 'surface-2' | 'surface-3';
type CompactNumberInputWidth = 'sm' | 'md' | 'lg' | 'full';

interface CompactNumberInputProps
  extends Omit<React.InputHTMLAttributes<HTMLInputElement>, 'type' | 'size'> {
  /**
   * Width rung. Closed union; see `CompactNumberInputWidth`. The
   * native HTML `size` attribute is intentionally suppressed (omitted
   * from the props extension) because in a popover/chip toolbar we
   * want the input to honor flex/grid layout, not its own intrinsic
   * char-count sizing — and TS would otherwise let callers pass a
   * numeric `size` that silently overrides our width class.
   */
  width?: CompactNumberInputWidth;
  /**
   * When `true`, applies `flex-1` so the input grows to fill the
   * remaining slot in a flex container. Independent of `width` —
   * combine e.g. `width='md' grow` to set a 56px minimum that
   * still expands.
   */
  grow?: boolean;
  /**
   * Background tier the input sits on. Determines the chip fill so the
   * input reads as nested inside its parent surface rather than competing
   * with it. Defaults to `surface-3` (the duration-popover rung). Pass
   * `surface-1` when the input lives directly on the page background
   * (settings panels), `surface-2` when it lives on a `surface-2` card
   * (recurrence editor inside a task-detail panel).
   */
  background?: CompactNumberInputBackground;
}

const BG_CLASS: Record<CompactNumberInputBackground, string> = {
  'surface-1': 'bg-surface-1',
  'surface-2': 'bg-surface-2',
  'surface-3': 'bg-surface-3',
};

const BORDER_CLASS: Record<CompactNumberInputBackground, string> = {
  'surface-1': 'border-surface-3',
  'surface-2': 'border-surface-3',
  'surface-3': 'border-surface-2',
};

const WIDTH_CLASS: Record<CompactNumberInputWidth, string> = {
  sm: 'w-12',
  md: 'w-14',
  lg: 'w-20',
  full: 'w-full',
};

const RECIPE =
  'validated-input text-text-primary text-xs px-2 py-1 ' +
  'rounded-r-control border outline-hidden ' +
  'focus-ring-soft placeholder:text-text-muted/60 ' +
  '[appearance:textfield] ' +
  '[&::-webkit-inner-spin-button]:appearance-none ' +
  '[&::-webkit-outer-spin-button]:appearance-none';

export const CompactNumberInput = forwardRef<HTMLInputElement, CompactNumberInputProps>(
  function CompactNumberInput(
    { width = 'md', grow = false, background = 'surface-3', className = '', ...rest },
    ref,
  ) {
    return (
      <input
        ref={ref}
        type="number"
        className={`${RECIPE} ${BG_CLASS[background]} ${BORDER_CLASS[background]} ${WIDTH_CLASS[width]}${grow ? ' flex-1' : ''} ${className}`}
        {...rest}
      />
    );
  },
);
