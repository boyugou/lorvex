import { useCallback, useEffect, useId, useMemo, useRef, useState } from 'react';
import { MAX_TITLE_LENGTH } from '@lorvex/shared/validation';
import type { CalendarEvent } from '@/lib/ipc/calendar';
import type { TranslationKey } from '@/lib/i18n';
import { prefersReducedMotion } from '@/lib/reducedMotion';
import { themedSwatch } from '@/lib/colors/themedSwatch';
import { AppSelect } from '@/components/ui/AppSelect';
import { AutosizingTextarea } from '@/components/ui/AutosizingTextarea';
import { CheckIcon } from '@/components/ui/icons';
import { DatePicker } from '@/components/ui/DatePicker';
import { SubmitButton } from '@/components/ui/SubmitButton';
import { Toggle } from '@/components/ui/Toggle';
import { Tooltip } from '@/components/ui/Tooltip';
import { ValidatedField } from '@/components/ui/ValidatedField';
import {
  handleRovingRadioGroupKeyDown,
  handleRovingRadioSpaceKey,
} from '@/components/ui/radioGroupKeyboard';
import { EVENT_COLORS, EVENT_COLOR_NAME_KEYS } from '../viewSupport';
import { EventRecurrenceFields } from './EventRecurrenceFields';
import { installEventFormEscapeRuntime } from './EventForm.runtime';
import { useEventFormController } from './useEventFormController';
import { validateEventSubmission } from './support';

export function EventForm({
  date,
  event,
  t,
  onDone,
  onCancel,
}: {
  date: string;
  event: CalendarEvent | null;
  t: (key: TranslationKey) => string;
  onDone: () => void;
  onCancel: () => void;
}) {
  const {
    titleRef,
    isEditing,
    title,
    setTitle,
    startDate,
    handleStartDateChange,
    useEndDate,
    handleUseEndDateChange,
    endDate,
    setEndDate,
    startTime,
    setStartTime,
    endTime,
    setEndTime,
    allDay,
    setAllDay,
    normalizedTimezone,
    timezoneOptions,
    handleTimezoneChange,
    recurrencePreset,
    handleRecurrencePresetChange,
    recurrenceInterval,
    handleRecurrenceIntervalChange,
    recurrenceEndCondition,
    handleRecurrenceEndConditionChange,
    normalizedRecurrenceUntil,
    setRecurrenceUntilDate,
    recurrenceWeekdays,
    toggleRecurrenceWeekday,
    effectiveStartDate,
    location,
    setLocation,
    description,
    setDescription,
    color,
    setColor,
    isDeleting,
    isSaving,
    handleDelete,
    handleSubmit,
  } = useEventFormController({
    date,
    event,
    t,
    onDone,
  });

  // Scroll form into view on mount. Honor
  // `prefers-reduced-motion` so users with macOS Reduce Motion enabled
  // (or any other platform's equivalent) get instant scroll instead
  // of a smooth animation — one of the top vestibular triggers.
  const formRef = useRef<HTMLFormElement>(null);
  const colorButtonRefs = useRef<Array<HTMLButtonElement | null>>([]);
  useEffect(() => {
    const prefersReduced = prefersReducedMotion(
      typeof window === 'undefined' ? undefined : window,
    );
    formRef.current?.scrollIntoView({
      behavior: prefersReduced ? 'auto' : 'smooth',
      block: 'nearest',
    });
  }, []);

  // a11y: surface form-level validation inline so screen
  // readers pick it up via `aria-errormessage`, not just via the
  // ephemeral toast (`role="status"` is only announced on subsequent
  // changes, and the toast disappears after a few seconds). We defer
  // rendering the errors until the user has attempted to submit — no
  // one wants to open an empty form and immediately see "title is
  // required".
  const [submitAttempted, setSubmitAttempted] = useState(false);
  // a11y: stable id linking the start/end time inputs to the
  // timezone help text so SR users hear "Times shown in <tz>" via
  // `aria-describedby`.
  const tzHelpId = useId();
  const effectiveEndDateForValidation = useEndDate ? (endDate || effectiveStartDate) : null;
  const titleError = submitAttempted && !title.trim() ? t('calendar.titleRequired') : null;
  // Memoize the deferred validation result so it only re-runs when
  // one of the validated inputs actually changes, not on every render
  // (every `setTitle`, `setStartTime`, etc.). Pinning the pattern
  // keeps a future field addition from compounding re-render cost.
  const deferredValidationError = useMemo(() => {
    if (!submitAttempted) return null;
    return validateEventSubmission({
      title,
      effectiveStartDate,
      recurrencePreset,
      recurrenceEndCondition,
      normalizedRecurrenceUntil,
      useEndDate,
      effectiveEndDate: effectiveEndDateForValidation,
      allDay,
      startTime,
      endTime,
    });
  }, [
    submitAttempted,
    title,
    effectiveStartDate,
    recurrencePreset,
    recurrenceEndCondition,
    normalizedRecurrenceUntil,
    useEndDate,
    effectiveEndDateForValidation,
    allDay,
    startTime,
    endTime,
  ]);
  const startDateError = deferredValidationError === 'missingStartDate'
    ? t('calendar.missingStartDate')
    : null;
  const endDateError = deferredValidationError === 'invalidDateRange'
    ? t('calendar.invalidDateRange')
    : null;
  // mirror the missingStartDate/invalidDateRange aria-invalid
  // affordance for the time range. When `invalidTimeRange` fires, both
  // start and end time inputs are part of the broken range; mark them
  // both so AT users hear the invalidity on whichever field they focus.
  const timeRangeInvalid = deferredValidationError === 'invalidTimeRange';
  const selectedColorIndex = EVENT_COLORS.findIndex((nextColor) => nextColor === color);
  const selectColorAtIndex = useCallback((index: number) => {
    const nextColor = EVENT_COLORS[index];
    if (!nextColor) return;
    setColor(nextColor);
  }, [setColor]);
  const focusColorAtIndex = useCallback((index: number) => {
    colorButtonRefs.current[index]?.focus();
  }, []);

  // Close on Escape key (use ref to avoid re-registering on every render)
  const onCancelRef = useRef(onCancel);
  onCancelRef.current = onCancel;
  useEffect(() => {
    return installEventFormEscapeRuntime({
      documentTarget: document,
      getFormRoot: () => formRef.current,
      getOnCancel: () => onCancelRef.current,
    });
  }, []);

  return (
    <form
      ref={formRef}
      onSubmit={(event_) => {
        setSubmitAttempted(true);
        void handleSubmit(event_);
      }}
      className="mt-3 p-3 rounded-r-control border border-surface-3 bg-surface-2/50 space-y-2.5"
    >
      <ValidatedField
        id="calendar-event-title"
        label={t('calendar.eventTitle')}
        showLabel={false}
        error={titleError}
      >
        {({ fieldProps }) => (
          <input
            {...fieldProps}
            ref={titleRef}
            type="text"
            value={title}
            onChange={(event_) => setTitle(event_.target.value)}
            maxLength={MAX_TITLE_LENGTH}
            placeholder={t('calendar.eventTitle')}
            aria-label={t('calendar.eventTitle')}
            className={`${fieldProps.className} w-full bg-transparent text-xs text-text-primary placeholder:text-text-muted outline-hidden focus-ring-soft border-b border-surface-3 pb-1.5`}
          />
        )}
      </ValidatedField>

      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <EventDateField
          label={t('calendar.startDate')}
          value={startDate}
          onChange={handleStartDateChange}
          error={startDateError}
        />
        {useEndDate ? (
          <EventDateField
            label={t('calendar.endDate')}
            value={endDate}
            minDate={startDate}
            onChange={setEndDate}
            error={endDateError}
          />
        ) : null}
      </div>

      <Toggle
        checked={useEndDate}
        onChange={(checked) => handleUseEndDateChange(checked)}
        label={t('calendar.multiDay')}
      />

      <Toggle
        checked={allDay}
        onChange={setAllDay}
        label={t('calendar.eventAllDay')}
      />

      {!allDay ? (
        <div className="space-y-1">
          <div className="flex items-center gap-2">
            <input
              type="time"
              value={startTime}
              onChange={(event_) => setStartTime(event_.target.value)}
              aria-label={t('calendar.startTime')}
              aria-describedby={tzHelpId}
              aria-invalid={timeRangeInvalid || undefined}
              data-theme-form-control="true"
              className="flex-1 bg-surface-2 text-xs text-text-primary border border-surface-3 rounded-r-control px-2.5 py-1.5 outline-hidden focus-ring-soft transition-colors hover:border-accent/30"
            />
            <span className="text-xs text-text-muted">–</span>
            <input
              type="time"
              value={endTime}
              onChange={(event_) => setEndTime(event_.target.value)}
              aria-label={t('calendar.endTime')}
              aria-describedby={tzHelpId}
              aria-invalid={timeRangeInvalid || undefined}
              data-theme-form-control="true"
              className="flex-1 bg-surface-2 text-xs text-text-primary border border-surface-3 rounded-r-control px-2.5 py-1.5 outline-hidden focus-ring-soft transition-colors hover:border-accent/30"
            />
          </div>
          {/* a11y: explicit tz-linkage so SR users know which
              zone the typed time is interpreted in. Sighted users get
              the same signal as a muted help line. The select below is
              the affordance to change it. */}
          <p id={tzHelpId} className="text-2xs text-text-muted">
            {t('calendar.timezoneHint')} {normalizedTimezone}
          </p>
        </div>
      ) : null}

      <label className="space-y-1 block">
        <span className="text-xs font-medium text-text-muted">
          {t('settings.timezone')}
        </span>
        <AppSelect
          value={normalizedTimezone}
          variant="muted"
          popoverLayer="modalPopover"
          onChange={(event_) => handleTimezoneChange(event_.target.value)}
          className="w-full bg-transparent text-text-primary rounded-r-control py-1"
        >
          {timezoneOptions.map((option) => (
            <option key={option} value={option}>
              {option}
            </option>
          ))}
        </AppSelect>
      </label>

      <EventRecurrenceFields
        t={t}
        recurrencePreset={recurrencePreset}
        onRecurrencePresetChange={handleRecurrencePresetChange}
        recurrenceInterval={recurrenceInterval}
        onRecurrenceIntervalChange={handleRecurrenceIntervalChange}
        recurrenceEndCondition={recurrenceEndCondition}
        onRecurrenceEndConditionChange={handleRecurrenceEndConditionChange}
        normalizedRecurrenceUntil={normalizedRecurrenceUntil}
        onRecurrenceUntilDateChange={setRecurrenceUntilDate}
        recurrenceWeekdays={recurrenceWeekdays}
        onToggleWeekday={toggleRecurrenceWeekday}
        effectiveStartDate={effectiveStartDate}
      />

      <label className="sr-only" htmlFor="calendar-event-location">{t('calendar.eventLocation')}</label>
      <input
        id="calendar-event-location"
        type="text"
        value={location}
        onChange={(event_) => setLocation(event_.target.value)}
        placeholder={t('calendar.eventLocation')}
        className="w-full bg-transparent text-xs text-text-secondary placeholder:text-text-muted outline-hidden focus-ring-soft border-b border-surface-3 pb-1.5"
      />

      <label className="sr-only" htmlFor="calendar-event-description">{t('calendar.eventDescription')}</label>
      <AutosizingTextarea
        id="calendar-event-description"
        value={description}
        onChange={(event_) => setDescription(event_.target.value)}
        placeholder={t('calendar.eventDescription')}
        minRows={2}
        maxRows={8}
        data-theme-form-control="true"
        className="w-full bg-transparent text-xs text-text-secondary placeholder:text-text-muted outline-hidden focus-ring-soft border border-surface-3 rounded-r-control p-2"
      />

      <div
        className="flex items-center gap-1.5"
        role="radiogroup"
        aria-label={t('calendar.colorSwatchLabel')}
        onKeyDown={(event_) => {
          handleRovingRadioGroupKeyDown({
            currentIndex: selectedColorIndex,
            focusOption: focusColorAtIndex,
            key: event_.key,
            onSelect: selectColorAtIndex,
            optionCount: EVENT_COLORS.length,
            preventDefault: () => event_.preventDefault(),
          });
        }}
      >
        {EVENT_COLORS.map((nextColor, index) => {
          const nameKey = EVENT_COLOR_NAME_KEYS[nextColor];
          const colorLabel = `${t('calendar.colorSwatchLabel')}: ${nameKey ? t(nameKey) : nextColor}`;
          const selected = color === nextColor;
          return (
            <Tooltip key={nextColor} label={colorLabel}>
              <button
                ref={(element) => { colorButtonRefs.current[index] = element; }}
                type="button"
                onClick={() => setColor(nextColor)}
                aria-label={colorLabel}
                role="radio"
                aria-checked={selected}
                tabIndex={selected ? 0 : -1}
                onKeyDown={(event_) => {
                  handleRovingRadioSpaceKey({
                    key: event_.key,
                    onSelect: () => setColor(nextColor),
                    preventDefault: () => event_.preventDefault(),
                  });
                }}
                // a11y: non-color indicator (checkmark) so the
                // selected swatch is distinguishable to users with color
                // vision deficiency or in high-contrast modes that
                // remap the ring color away from the swatch outline.
                className={`relative w-5 h-5 rounded-full transition-transform inline-flex items-center justify-center ${selected ? 'scale-110 ring-2 ring-accent ring-offset-1 ring-offset-surface-2' : 'hover:scale-110 motion-reduce:hover:scale-100'} focus-ring-soft`}
                style={{ backgroundColor: themedSwatch(nextColor, 'tile') }}
              >
                {selected ? (
                  <CheckIcon
                    aria-hidden="true"
                    className="w-3 h-3 text-white drop-shadow-[var(--shadow-event-card)]"
                  />
                ) : null}
              </button>
            </Tooltip>
          );
        })}
      </div>

      <div className="flex items-center justify-between gap-2 pt-1">
        {isEditing ? (
          <button
            type="button"
            disabled={isDeleting}
            onClick={() => { void handleDelete(); }}
            className="text-xs text-danger/70 hover:text-danger transition-colors rounded-r-control focus-ring-soft disabled:opacity-50"
          >
            {isDeleting ? t('common.deleting') : t('calendar.deleteEvent')}
          </button>
        ) : (
          <div />
        )}
        <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={onCancel}
            disabled={isDeleting}
            className="text-xs text-text-muted hover:text-text-primary transition-colors rounded-r-control focus-ring-soft"
          >
            {t('common.cancel')}
          </button>
          <SubmitButton
            isSaving={isSaving}
            disabled={!title.trim() || isDeleting}
            className="text-xs bg-accent text-on-accent active:scale-[0.97] px-3 py-1 rounded-r-control hover:bg-accent/90 disabled:opacity-50 disabled:cursor-not-allowed focus-ring-strong"
          >
            {isEditing ? t('common.save') : t('common.add')}
          </SubmitButton>
        </div>
      </div>
    </form>
  );
}

function EventDateField({ label, value, minDate, onChange, error }: {
  label: string;
  value: string;
  minDate?: string;
  onChange: (date: string) => void;
  error?: string | null;
}) {
  const [open, setOpen] = useState(false);
  const anchorRef = useRef<HTMLButtonElement>(null);

  // the date picker trigger is a <button>, not an <input>,
  // so `aria-invalid` sits on the button itself and the error
  // paragraph is linked via `aria-errormessage` through the
  // `ValidatedField` render prop. `showLabel=false` preserves the
  // existing visual hierarchy (muted span label) while screen readers
  // still get the label via `aria-label` on the trigger.
  return (
    <ValidatedField
      label={label}
      showLabel={false}
      error={error ?? null}
      className="space-y-1"
    >
      {({ fieldProps }) => (
        <>
          <span className="text-xs font-medium text-text-muted">{label}</span>
          <button
            {...fieldProps}
            ref={anchorRef}
            type="button"
            onClick={() => setOpen(true)}
            aria-label={label}
            className={`${fieldProps.className} w-full bg-transparent text-start text-xs text-text-primary border border-surface-3 rounded-r-control px-2 py-1 hover:border-accent/50 transition-colors`}
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
        </>
      )}
    </ValidatedField>
  );
}
