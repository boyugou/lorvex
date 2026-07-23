import { useRef, useState } from 'react';
import { useI18n } from '@/lib/i18n';
import { isImeComposing } from '@/lib/ime';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { addYmdDays } from '@/lib/dayContextMath';
import { ToggleChip } from './ToggleChip';
import type { DatePickerQuickChip } from './DatePicker.controller';

interface DatePickerQuickChipsProps {
  chips: DatePickerQuickChip[];
  value: string | null;
  isMobile: boolean;
  onSelectDate: (ymd: string) => void;
}

/**
 * Parses a relative-offset stepper string.
 *
 * Accepts: bare integers ("3" = 3 days from today), or `<n>d` /
 * `<n>w` (`d` for days, `w` for weeks). Returns the offset in days
 * (positive or negative) or `null` if the string isn't a valid
 * offset expression. The stepper is offered alongside the day-grid
 * so a user typing `+3` (or `2w`) lands on a date five seconds
 * faster than month-navigating the grid.
 */
function parseStepperOffset(raw: string): number | null {
  const trimmed = raw.trim();
  if (!trimmed) return null;
  // Strip a leading `+` for ergonomic typing (`+3` reads as
  // "three days from today" but the unary plus is meaningless).
  const normalized = trimmed.startsWith('+') ? trimmed.slice(1) : trimmed;
  const match = /^(-?\d+)\s*([dw])?$/i.exec(normalized);
  if (!match) return null;
  const n = Number(match[1]);
  if (!Number.isFinite(n)) return null;
  const unit = (match[2] ?? 'd').toLowerCase();
  return unit === 'w' ? n * 7 : n;
}

export function DatePickerQuickChips({
  chips,
  value,
  isMobile,
  onSelectDate,
}: DatePickerQuickChipsProps) {
  const { t } = useI18n();
  const dayContext = useConfiguredDayContext();
  const [stepperValue, setStepperValue] = useState('');
  const [stepperError, setStepperError] = useState<string | null>(null);
  // Imperative shake replay via the Web Animations API. A `key`-based
  // remount would drop focus from the input mid-typing on every
  // rejection — replaying through `element.animate(...)` keeps the
  // node identity (and thus the caret/IME state) stable.
  const stepperInputRef = useRef<HTMLInputElement>(null);
  const shakeAnimationRef = useRef<Animation | null>(null);

  const playShake = () => {
    const node = stepperInputRef.current;
    if (!node) return;
    const prefersReducedMotion =
      typeof window !== 'undefined' &&
      window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (prefersReducedMotion) return;
    shakeAnimationRef.current?.cancel();
    shakeAnimationRef.current = node.animate(
      [
        { transform: 'translateX(0)' },
        { transform: 'translateX(-6px)' },
        { transform: 'translateX(5px)' },
        { transform: 'translateX(-4px)' },
        { transform: 'translateX(3px)' },
        { transform: 'translateX(-2px)' },
        { transform: 'translateX(0)' },
      ],
      { duration: 320, easing: 'cubic-bezier(.36,.07,.19,.97)' },
    );
  };

  const chipClassOverride = isMobile
    ? 'min-h-11 px-3 py-2 text-sm'
    : '';

  const applyStepper = () => {
    const offset = parseStepperOffset(stepperValue);
    if (offset === null) {
      setStepperError(t('datePicker.stepperInvalid'));
      // Trigger a motion-safe horizontal shake — the inline error
      // text + border swap alone aren't loud enough to catch a fast
      // typist. `prefers-reduced-motion` users get only the static
      // error message; replaying via the Web Animations API instead
      // of `key`-remount keeps focus + IME state on the input.
      playShake();
      return;
    }
    const target = addYmdDays(dayContext.todayYmd, offset);
    setStepperError(null);
    setStepperValue('');
    onSelectDate(target);
  };

  return (
    <div className="mb-3">
      <div className={`flex gap-1.5 flex-wrap ${isMobile ? 'gap-2' : ''}`}>
        {chips.map((chip) => (
          <ToggleChip
            key={chip.date}
            size="sm"
            onClick={() => onSelectDate(chip.date)}
            selected={value === chip.date}
            className={chipClassOverride}
          >
            {chip.label}
          </ToggleChip>
        ))}
      </div>
      {/* +N stepper. Power users (especially keyboard-only users)
          can type "3" or "2w" to leap to that offset without
          scrubbing the grid. The bare-input form is intentionally
          terse — a labeled SubmitButton would shift visual weight
          from the grid below. */}
      <form
        className="mt-2 flex items-center gap-1.5"
        onSubmit={(e) => {
          e.preventDefault();
          applyStepper();
        }}
      >
        <input
          ref={stepperInputRef}
          type="text"
          // 95% of stepper inputs are bare integers (`3`, `-2`); the
          // `d`/`w` suffix is rare. `numeric` summons a number-first
          // keyboard on mobile (still allows the `d`/`w` letters via
          // the symbol pane) and matches the DatePicker convention.
          inputMode="numeric"
          value={stepperValue}
          onChange={(e) => {
            setStepperValue(e.target.value);
            if (stepperError) setStepperError(null);
          }}
          onKeyDown={(e) => {
            // Romaji finalization on Enter would otherwise submit
            // the surrounding form mid-composition. `preventDefault`
            // suppresses the implicit-submit behavior for the
            // composition-finalizing keystroke.
            if (isImeComposing(e)) {
              if (e.key === 'Enter') e.preventDefault();
            }
          }}
          placeholder={t('datePicker.stepperPlaceholder')}
          aria-label={t('datePicker.stepperLabel')}
          aria-invalid={stepperError ? 'true' : undefined}
          className={`flex-1 min-w-0 px-2.5 py-1 rounded-r-control border bg-surface-2/40 text-xs text-text-primary placeholder:text-text-muted/60 transition-colors focus-ring-soft ${
            stepperError ? 'border-danger/40' : 'border-card hover:border-popover'
          }`}
        />
        <button
          type="submit"
          disabled={stepperValue.trim().length === 0}
          className="shrink-0 text-xs px-2.5 py-1 rounded-r-control bg-surface-2 text-text-secondary hover:bg-surface-3 disabled:opacity-50 disabled:cursor-not-allowed transition-colors focus-ring-soft"
        >
          {t('datePicker.stepperApply')}
        </button>
      </form>
      {stepperError && (
        <p className="mt-1 text-2xs text-danger" role="alert" aria-live="polite">{stepperError}</p>
      )}
    </div>
  );
}
