import { useId, useRef, useState } from 'react';
import { AppSelect } from '@/components/ui/AppSelect';
import { CompactNumberInput } from '@/components/ui/CompactNumberInput';
import { DatePicker } from '@/components/ui/DatePicker';
import type { TranslationKey } from '@/lib/i18n';
import { RECURRENCE_INTERVAL_MAX, RECURRENCE_INTERVAL_MIN } from '@/lib/recurrenceInterval';
import {
  type CalendarRecurrenceEndCondition,
  type CalendarRecurrencePreset,
  type WeekdayCode,
  WEEKDAY_OPTIONS,
} from '../calendarViewUtils';

export function EventRecurrenceFields({
  t,
  recurrencePreset,
  onRecurrencePresetChange,
  recurrenceInterval,
  onRecurrenceIntervalChange,
  recurrenceEndCondition,
  onRecurrenceEndConditionChange,
  normalizedRecurrenceUntil,
  onRecurrenceUntilDateChange,
  recurrenceWeekdays,
  onToggleWeekday,
  effectiveStartDate,
}: {
  t: (key: TranslationKey) => string;
  recurrencePreset: CalendarRecurrencePreset;
  onRecurrencePresetChange: (value: string) => void;
  recurrenceInterval: number;
  onRecurrenceIntervalChange: (value: string) => void;
  recurrenceEndCondition: CalendarRecurrenceEndCondition;
  onRecurrenceEndConditionChange: (value: string) => void;
  normalizedRecurrenceUntil: string;
  onRecurrenceUntilDateChange: (value: string) => void;
  recurrenceWeekdays: WeekdayCode[];
  onToggleWeekday: (value: WeekdayCode) => void;
  effectiveStartDate: string;
}) {
  // a11y: the recurrence interval input accepts freeform numbers but
  // only the shared recurrence interval range is valid. Mark the field invalid inline so screen
  // readers hear an out-of-range value immediately rather than only
  // discovering the rejection at submit time.
  const intervalErrorId = useId();
  const intervalInvalid =
    !Number.isFinite(recurrenceInterval)
    || !Number.isInteger(recurrenceInterval)
    || recurrenceInterval < RECURRENCE_INTERVAL_MIN
    || recurrenceInterval > RECURRENCE_INTERVAL_MAX;
  return (
    <>
      <label className="space-y-1 block">
        <span className="text-xs font-medium text-text-muted">
          {t('task.recurrence')}
        </span>
        <AppSelect
          value={recurrencePreset}
          variant="muted"
          popoverLayer="modalPopover"
          onChange={(event_) => onRecurrencePresetChange(event_.target.value)}
          className="w-full bg-transparent text-text-primary rounded-r-control py-1"
        >
          <option value="none">{t('calendar.recurrence.none')}</option>
          <option value="daily">{t('calendar.recurrence.daily')}</option>
          <option value="weekly">{t('calendar.recurrence.weekly')}</option>
          <option value="monthly">{t('calendar.recurrence.monthly')}</option>
          <option value="yearly">{t('calendar.recurrence.yearly')}</option>
          {recurrencePreset === 'advanced' ? (
            <option value="advanced">{t('settings.advanced')}</option>
          ) : null}
        </AppSelect>
      </label>
      {recurrencePreset !== 'none' && recurrencePreset !== 'advanced' ? (
        <div className="space-y-2 rounded-r-control border border-surface-3 bg-surface-1/40 p-2">
          <label className="space-y-1 block">
            <span className="text-xs font-medium text-text-muted">
              {t('calendar.recurrence.interval')}
            </span>
            <CompactNumberInput
              min={RECURRENCE_INTERVAL_MIN}
              max={RECURRENCE_INTERVAL_MAX}
              step={1}
              value={recurrenceInterval}
              onChange={(event_) => onRecurrenceIntervalChange(event_.target.value)}
              aria-invalid={intervalInvalid}
              aria-errormessage={intervalInvalid ? intervalErrorId : undefined}
              background="surface-2"
              width="full"
              className="px-2.5 py-1.5 transition-colors hover:border-accent/30"
            />
            {intervalInvalid && (
              <p id={intervalErrorId} role="alert" className="text-3xs text-danger">
                {t('calendar.recurrence.intervalInvalid')}
              </p>
            )}
          </label>
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
            <label className="space-y-1 block">
              <span className="text-xs font-medium text-text-muted">
                {t('calendar.recurrence.end')}
              </span>
              <AppSelect
                value={recurrenceEndCondition}
                variant="muted"
                popoverLayer="modalPopover"
                onChange={(event_) => onRecurrenceEndConditionChange(event_.target.value)}
                className="w-full bg-transparent text-text-primary rounded-r-control py-1"
              >
                <option value="never">{t('calendar.recurrence.endNever')}</option>
                <option value="onDate">{t('calendar.recurrence.endOnDate')}</option>
              </AppSelect>
            </label>
            {recurrenceEndCondition === 'onDate' ? (
              <EventRecurrenceUntilDate
                value={normalizedRecurrenceUntil}
                minDate={effectiveStartDate}
                onChange={onRecurrenceUntilDateChange}
                t={t}
              />
            ) : null}
          </div>
          {recurrencePreset === 'weekly' ? (
            <div className="space-y-1">
              <span className="text-xs font-medium text-text-muted">
                {t('calendar.recurrence.weekdays')}
              </span>
              <div
                role="group"
                aria-label={t('calendar.recurrence.weekdays')}
                className="flex flex-wrap gap-1.5"
              >
                {WEEKDAY_OPTIONS.map((option) => {
                  const selected = recurrenceWeekdays.includes(option.code);
                  return (
                    <button
                      key={option.code}
                      type="button"
                      aria-pressed={selected}
                      onClick={() => onToggleWeekday(option.code)}
                      className={`px-2 py-1 rounded-r-control text-xs border transition-colors focus-ring-soft ${
                        selected
                          ? 'bg-accent/20 border-accent text-accent'
                          : 'bg-surface-2 border-surface-3 text-text-secondary hover:text-text-primary'
                      }`}
                    >
                      {t(option.labelKey)}
                    </button>
                  );
                })}
              </div>
            </div>
          ) : null}
        </div>
      ) : null}
    </>
  );
}

function EventRecurrenceUntilDate({ value, minDate, onChange, t }: {
  value: string;
  minDate: string;
  onChange: (date: string) => void;
  t: (key: TranslationKey) => string;
}) {
  const [open, setOpen] = useState(false);
  const anchorRef = useRef<HTMLButtonElement>(null);
  const fieldLabel = t('task.recurrence.until');
  const accessibleValue = value || t('common.none');

  return (
    <div className="space-y-1 block">
      <span className="text-xs font-medium text-text-muted">
        {fieldLabel}
      </span>
      <button
        ref={anchorRef}
        type="button"
        aria-label={`${fieldLabel}: ${accessibleValue}`}
        onClick={() => setOpen(true)}
        className="w-full bg-transparent text-start text-xs text-text-primary border border-surface-3 rounded-r-control px-2 py-1 hover:border-accent/50 transition-colors"
      >
        {value || '—'}
      </button>
      {open && (
        <DatePicker
          value={value || null}
          onChange={(date) => { if (date) onChange(date); }}
          onClose={() => setOpen(false)}
          anchorRef={anchorRef}
          showQuickChips={false}
          showClearButton={false}
          minDate={minDate}
          popoverLayer="modalPopover"
        />
      )}
    </div>
  );
}
