import { useEffect } from 'react';
import { getPreference } from '@/lib/ipc/settings';
import { reportClientError } from '@/lib/errors/errorLogging';
import { parsePreferenceJson } from '@/lib/preferences/parser';
import { PREF_TIMEZONE } from '@/lib/preferences/keys';
import { normalizeTimezonePreference } from '@/lib/dates/timezone';
import { weekdayCodeFromDate } from '../calendarViewUtils';
import type { EventFormState } from './state';

interface UseEventFormEffectsArgs {
  date: string;
  eventTimezone: string | null | undefined;
  state: Pick<
    EventFormState,
    | 'titleRef'
    | 'systemTimezone'
    | 'hasEventTimezone'
    | 'timezoneWasEditedRef'
    | 'setTimezone'
    | 'recurrencePreset'
    | 'startDate'
    | 'setRecurrenceWeekdays'
    | 'recurrenceEndCondition'
    | 'recurrenceUntilDate'
    | 'setRecurrenceEndCondition'
    | 'setRecurrenceUntilDate'
  >;
}

export function useEventFormEffects({
  date,
  eventTimezone,
  state,
}: UseEventFormEffectsArgs): void {
  const {
    hasEventTimezone,
    recurrenceEndCondition,
    recurrencePreset,
    recurrenceUntilDate,
    setRecurrenceEndCondition,
    setRecurrenceUntilDate,
    setRecurrenceWeekdays,
    setTimezone,
    startDate,
    systemTimezone,
    timezoneWasEditedRef,
    titleRef,
  } = state;

  useEffect(() => {
    titleRef.current?.focus();
  }, [titleRef]);

  useEffect(() => {
    timezoneWasEditedRef.current = false;
    setTimezone(normalizeTimezonePreference(eventTimezone, systemTimezone));
  }, [eventTimezone, setTimezone, systemTimezone, timezoneWasEditedRef]);

  useEffect(() => {
    if (hasEventTimezone) return;
    let cancelled = false;
    const loadAppTimezonePreference = async () => {
      try {
        const timezonePrefRaw = await getPreference(PREF_TIMEZONE);
        if (cancelled || timezoneWasEditedRef.current) return;
        const timezonePref = parsePreferenceJson(timezonePrefRaw);
        setTimezone(normalizeTimezonePreference(timezonePref, systemTimezone));
      } catch (error) {
        reportClientError(
          'frontend.calendar.timezonePreference',
          'Failed to load calendar timezone preference',
          error,
          systemTimezone,
          'warn',
        );
      }
    };
    void loadAppTimezonePreference();
    return () => {
      cancelled = true;
    };
  }, [hasEventTimezone, setTimezone, systemTimezone, timezoneWasEditedRef]);

  useEffect(() => {
    if (recurrencePreset !== 'weekly') return;
    setRecurrenceWeekdays((previous) => (
      previous.length > 0 ? previous : [weekdayCodeFromDate(startDate)]
    ));
  }, [recurrencePreset, setRecurrenceWeekdays, startDate]);

  useEffect(() => {
    if (recurrencePreset === 'none') {
      setRecurrenceEndCondition('never');
      return;
    }
    if (recurrenceEndCondition === 'onDate' && !recurrenceUntilDate) {
      setRecurrenceUntilDate(startDate || date);
    }
  }, [
    date,
    recurrenceEndCondition,
    recurrencePreset,
    recurrenceUntilDate,
    setRecurrenceEndCondition,
    setRecurrenceUntilDate,
    startDate,
  ]);
}
