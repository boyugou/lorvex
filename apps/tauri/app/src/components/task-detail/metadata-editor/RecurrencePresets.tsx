import { useCallback, useRef } from 'react';
import { CompactNumberInput } from '@/components/ui/CompactNumberInput';
import {
  handleRovingRadioGroupKeyDown,
  handleRovingRadioSpaceKey,
} from '@/components/ui/radioGroupKeyboard';
import {
  BYDAY_OPTIONS,
  FREQ_OPTIONS,
  normalizeRecurrenceIntervalInput,
  type RecurrenceRule,
  type Translator,
} from './shared';

/**
 * Frequency / interval / BYDAY chip controls for the recurrence
 * editor. "Presets" in the sense that these chips encode the canonical
 * recurrence preset axes (every N days/weeks/months/years, plus the
 * weekly weekday picker) the AI and the human share — the deeper rule
 * editing (UNTIL date) lives in `RecurrenceRuleEditor`.
 *
 * Roving-tabindex keyboard semantics on the FREQ group: ArrowLeft /
 * ArrowRight move focus + select; Space / Enter on the focused option
 * selects it. The BYDAY chips are independent toggles, no roving.
 */
export function RecurrencePresets({
  freq,
  setFreq,
  repeatInterval,
  setRepeatInterval,
  byday,
  toggleDay,
  intervalInvalid,
  intervalErrorId,
  t,
}: {
  freq: RecurrenceRule['freq'];
  setFreq: (next: RecurrenceRule['freq']) => void;
  repeatInterval: number;
  setRepeatInterval: (next: number) => void;
  byday: string[];
  toggleDay: (code: string) => void;
  intervalInvalid: boolean;
  intervalErrorId: string;
  t: Translator;
}) {
  const freqButtonRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const selectedFreqIndex = FREQ_OPTIONS.findIndex((option) => option.value === freq);
  const selectFreqAtIndex = useCallback((index: number) => {
    const option = FREQ_OPTIONS[index];
    if (!option) return;
    setFreq(option.value);
  }, [setFreq]);
  const focusFreqAtIndex = useCallback((index: number) => {
    freqButtonRefs.current[index]?.focus();
  }, []);

  return (
    <>
      <div className="flex items-center gap-2 flex-wrap">
        <span className="text-xs text-text-muted">{t('task.recurrence.every')}</span>
        <CompactNumberInput
          min={1}
          max={99}
          value={repeatInterval}
          onChange={(event) => {
            setRepeatInterval(normalizeRecurrenceIntervalInput(event.target.value));
          }}
          width="sm"
          background="surface-2"
          className="py-0.5 text-center"
          aria-label={t('task.recurrence.interval')}
          aria-invalid={intervalInvalid}
          aria-errormessage={intervalInvalid ? intervalErrorId : undefined}
        />
        <div
          role="radiogroup"
          aria-label={t('task.recurrence')}
          onKeyDown={(event) => {
            handleRovingRadioGroupKeyDown({
              currentIndex: selectedFreqIndex,
              focusOption: focusFreqAtIndex,
              key: event.key,
              onSelect: selectFreqAtIndex,
              optionCount: FREQ_OPTIONS.length,
              preventDefault: () => event.preventDefault(),
            });
          }}
          className="flex rounded-r-control overflow-hidden border border-surface-3"
        >
          {FREQ_OPTIONS.map((option, index) => (
            <button
              ref={(element) => { freqButtonRefs.current[index] = element; }}
              type="button"
              role="radio"
              aria-checked={freq === option.value}
              tabIndex={freq === option.value ? 0 : -1}
              key={option.value}
              onClick={() => {
                setFreq(option.value);
              }}
              onKeyDown={(event) => {
                handleRovingRadioSpaceKey({
                  key: event.key,
                  onSelect: () => setFreq(option.value),
                  preventDefault: () => event.preventDefault(),
                });
              }}
              className={`px-2.5 py-1 text-xs transition-colors focus-ring-soft ${
                freq === option.value
                  ? 'bg-accent text-on-accent active:scale-[0.97]'
                  : 'bg-surface-2 text-text-muted hover:text-text-primary'
              }`}
            >
              {t(option.labelKey)}
            </button>
          ))}
        </div>
      </div>
      {intervalInvalid && (
        <p id={intervalErrorId} role="alert" className="text-3xs text-danger">
          {t('task.recurrence.intervalInvalid')}
        </p>
      )}

      {freq === 'WEEKLY' && (
        <div className="flex gap-1 flex-wrap">
          {BYDAY_OPTIONS.map((option) => {
            const active = byday.includes(option.code);
            return (
              <button
                type="button"
                aria-pressed={active}
                key={option.code}
                onClick={() => toggleDay(option.code)}
                className={`px-2 py-1 rounded-r-control text-xs border transition-colors focus-ring-soft ${
                  active
                    ? 'bg-accent text-on-accent active:scale-[0.97] border-accent'
                    : 'bg-surface-2 text-text-muted border-surface-3 hover:border-accent/50 hover:text-accent'
                }`}
              >
                {t(option.labelKey)}
              </button>
            );
          })}
        </div>
      )}
    </>
  );
}
