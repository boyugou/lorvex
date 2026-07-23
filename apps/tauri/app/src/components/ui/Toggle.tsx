import { useId } from 'react';

interface ToggleBaseProps {
  checked: boolean;
  onChange: (checked: boolean) => void;
  disabled?: boolean;
  /** Secondary description text rendered below the label. */
  description?: string;
  /**
   * Optional DOM id for the underlying switch input. When provided, an
   * external `<label htmlFor={id}>` can target this toggle so clicking the
   * label activates the switch. When omitted, a `useId()` value is used.
   */
  id?: string;
}

type ToggleAccessibleName =
  | {
      /** When provided, renders a full-width row with label on the left and toggle on the right. */
      label: string;
      ariaLabel?: never;
      ariaLabelledBy?: never;
    }
  | {
      label?: undefined;
      /**
       * Accessible name for the switch when no visible `label` is rendered.
       * Required whenever the toggle has no associated label element.
       */
      ariaLabel: string;
      ariaLabelledBy?: never;
    }
  | {
      label?: undefined;
      ariaLabel?: never;
      /**
       * External accessible name reference for layouts that keep visible text
       * outside the Toggle component.
       */
      ariaLabelledBy: string;
    };

type ToggleProps = ToggleBaseProps & ToggleAccessibleName;

/**
 * Apple platforms-style toggle switch.
 *
 * - 36 x 20 px pill track (bg-surface-3 off, bg-accent on)
 * - 16 px white thumb with subtle shadow, slides with 150 ms transition
 * - Uses a real checkbox input with `role="switch"` so labels activate it natively
 * - Focus-visible ring for keyboard navigation
 */
export function Toggle({
  checked,
  onChange,
  disabled = false,
  label,
  description,
  id: externalId,
  ariaLabel,
  ariaLabelledBy,
}: ToggleProps) {
  const autoId = useId();
  const id = externalId ?? autoId;
  const descriptionId = description ? `${id}-description` : undefined;

  const track = (
    <label
      className={`
        relative inline-flex shrink-0 w-9 h-5 rounded-full transition-transform duration-150 ease-in-out
        ${disabled ? 'opacity-50 cursor-not-allowed' : 'cursor-pointer active:scale-[0.97]'}
      `}
    >
      <input
        id={id}
        type="checkbox"
        role="switch"
        checked={checked}
        aria-label={label || ariaLabelledBy ? undefined : ariaLabel}
        aria-labelledby={label ? undefined : ariaLabelledBy}
        aria-describedby={descriptionId}
        disabled={disabled}
        onChange={(event) => onChange(event.currentTarget.checked)}
        className={`
          peer absolute -inset-x-1 -inset-y-3 z-[var(--z-elevated)] m-0 appearance-none rounded-full opacity-0
          ${disabled ? 'cursor-not-allowed' : 'cursor-pointer'}
        `}
      />
      {/* visible track is 36x20 - well under WCAG
        2.5.5 (Target Size) and Apple HIG's 44x44 minimum touch target.
        Add an invisible expander that grows the hit-test box to 44x44
        without changing the visual footprint. `-inset-x-1` widens 36
        → 36+8 = 44; `-inset-y-3` heightens 20 → 20+24 = 44. Mirrors
        the same trick TaskCardActionButton uses for its 24x24 circle.
        The actual input owns that expanded hit box, so visual and text
        labels both activate the same native control.
      */}
      <span
        aria-hidden
        className={`
          pointer-events-none absolute inset-0 rounded-full transition-colors duration-150 ease-in-out
          peer-focus-visible:outline peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2
          peer-focus-visible:outline-accent peer-focus-visible:shadow-[0_0_0_2px_var(--toggle-ring-cutout)]
          ${checked ? 'bg-accent' : 'bg-surface-3'}
        `}
      />
      <span
        aria-hidden
        className={`
          pointer-events-none absolute top-[2px] inline-block w-4 h-4 rounded-full shadow-[var(--shadow-tooltip)]
          transition-[inset-inline-start,inset-inline-end,background-color] duration-150 ease-in-out
          ${checked
            ? 'end-[2px] bg-surface-1'
            /*
             * a pure `bg-white` knob on the `bg-surface-3`
             * track vanishes on light themes where surface-3 is already
             * near-white. Use surface-0 in the off-state so the knob
             * keeps visible contrast on both dark and light palettes;
             * the on-state stays surface-1 to read crisply against the
             * accent fill of the active track.
             */
            : 'start-[2px] bg-surface-0'}
        `}
      />
    </label>
  );

  if (!label) return track;

  return (
    <div className="flex items-center justify-between gap-3">
      <div className="min-w-0">
        <label htmlFor={id} className={`text-sm text-text-secondary ${disabled ? '' : 'cursor-pointer'}`}>
          {label}
        </label>
        {description && (
          <p id={descriptionId} className="text-xs text-text-muted mt-0.5">{description}</p>
        )}
      </div>
      {track}
    </div>
  );
}
