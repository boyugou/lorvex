import type { CalendarEvent } from '@/lib/ipc/calendar';
import type { TranslationKey } from '@/lib/i18n';
import { parseTimeToMinutes } from '@/lib/timeUtils';

import type {
  CalendarRecurrenceEndCondition,
  CalendarRecurrencePreset,
} from '../calendarViewUtils';

export type EventFormControllerInput = {
  date: string;
  event: CalendarEvent | null;
  t: (key: TranslationKey) => string;
  onDone: () => void;
};

interface EventFormSubmissionState {
  title: string;
  effectiveStartDate: string;
  allDay: boolean;
  startTime: string;
  endTime: string;
  effectiveEndDate: string | null;
  recurrenceRaw: string | null;
  normalizedTimezone: string;
  location: string;
  description: string;
  color: string;
  /** True when the form is editing an existing event; gates the
   * auto-derive "no end time → +1h" logic so we don't silently grow
   * the duration of a previously-saved point-in-time event when the
   * user only meant to edit a different field. */
  isEditing: boolean;
}

interface EventFormValidationState {
  title: string;
  effectiveStartDate: string;
  recurrencePreset: CalendarRecurrencePreset;
  recurrenceEndCondition: CalendarRecurrenceEndCondition;
  normalizedRecurrenceUntil: string;
  useEndDate: boolean;
  effectiveEndDate: string | null;
  allDay: boolean;
  startTime: string;
  endTime: string;
}

export function buildEventPayload({
  allDay,
  color,
  description,
  effectiveEndDate,
  effectiveStartDate,
  location,
  normalizedTimezone,
  recurrenceRaw,
  startTime,
  title,
  endTime,
  isEditing,
}: EventFormSubmissionState) {
  // Auto-promote "no time entered, all-day not explicitly checked" into
  // an all-day event. Quick-adding "Lunch with Sarah on May 24" without a time
  // creates an all-day entry rather than rejecting at the backend with
  // "timed event must carry start_time".
  //
  // The promoted form sends `all_day: true` AND clears both time fields,
  // which is the shape the domain's `CalendarEventTiming::from_flat_fields`
  // expects. If the user explicitly toggled "all day" we honour it;
  // if they entered a start_time we honour that too.
  const trimmedStart = startTime?.trim() ?? '';
  const trimmedEnd = endTime?.trim() ?? '';
  const effectiveAllDay = allDay || (trimmedStart === '' && trimmedEnd === '');
  // Auto-derive `end_time` when the user gave a `start_time` but no
  // `end_time`. Lorvex picks one hour so a timed quick-add persists as
  // a normal calendar block instead of a point-in-time placeholder.
  //
  // Why this matters: the prior behaviour stored
  // `start_time = "14:00", end_time = NULL` as a "point-in-time"
  // event. The week timeline renders that as a 30-minute visual
  // placeholder (via the `WEEK_TIMELINE_DEFAULT_EVENT_DURATION`
  // fallback), but the underlying row still has `end_time = NULL`, so
  // a later edit-form-open shows an empty End Time field even though
  // the chip looked like a normal 30-min meeting. Deriving the end at
  // save time makes the persisted row match what the user saw.
  //
  // Domain-side considerations:
  //   - multi-day timed events REQUIRE `end_time`; the prior shape
  //     surfaced a typed Validation toast "multi-day timed calendar
  //     event must carry end_time" from `from_flat_fields`. Auto-deriving
  //     here means the user no longer has to figure that out.
  //   - the +1h overflow case (e.g. start at 23:30) clamps to 23:59
  //     instead of crossing into the next day. Cross-day timed events
  //     require BOTH a different `end_date` AND end_time, which the
  //     form already handles via the "use end date" toggle — auto-
  //     promoting to multi-day here would surprise the user.
  const derivedEndTime = (() => {
    if (effectiveAllDay) return null;
    if (trimmedEnd) return trimmedEnd;
    // Edit mode: an existing event that was stored point-in-time
    // (`end_time = NULL`) shouldn't silently inflate to a 1-hour event
    // just because the user opened the form to change an unrelated
    // field. Honour the empty end-time on edit so the row's shape is
    // preserved end-to-end. Create mode gets the +1h default so new
    // events look right in the timeline and round-trip correctly.
    if (isEditing) return null;
    if (!trimmedStart) return null;
    const startMin = parseTimeToMinutes(trimmedStart);
    if (startMin === null) return null;
    const targetMin = Math.min(startMin + 60, 23 * 60 + 59);
    if (targetMin <= startMin) return null; // skip when start is at/past 23:59
    return formatMinutesAsHHMM(targetMin);
  })();
  return {
    title: title.trim(),
    start_date: effectiveStartDate,
    start_time: effectiveAllDay ? null : (trimmedStart || null),
    end_date: effectiveEndDate,
    end_time: derivedEndTime,
    all_day: effectiveAllDay,
    recurrence: recurrenceRaw,
    location: location.trim() || null,
    description: description.trim() || null,
    timezone: normalizedTimezone,
    color,
  };
}

function formatMinutesAsHHMM(totalMinutes: number): string {
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  return `${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`;
}

export function buildErrorContext({
  allDay,
  effectiveEndDate,
  effectiveStartDate,
  normalizedTimezone,
  recurrenceRaw,
}: Pick<
  EventFormSubmissionState,
  'allDay' | 'effectiveEndDate' | 'effectiveStartDate' | 'normalizedTimezone' | 'recurrenceRaw'
>) {
  return {
    start_date: effectiveStartDate,
    end_date: effectiveEndDate,
    all_day: allDay,
    recurrence: recurrenceRaw ? 'set' : 'none',
    timezone: normalizedTimezone,
  };
}

export function validateEventSubmission({
  allDay,
  effectiveEndDate,
  effectiveStartDate,
  endTime,
  normalizedRecurrenceUntil,
  recurrenceEndCondition,
  recurrencePreset,
  startTime,
  title,
  useEndDate,
}: EventFormValidationState): 'missingTitle' | 'missingStartDate' | 'invalidDateRange' | 'invalidTimeRange' | null {
  if (!title.trim()) {
    return 'missingTitle';
  }
  if (!effectiveStartDate) {
    return 'missingStartDate';
  }
  if (
    recurrencePreset !== 'none'
    && recurrenceEndCondition === 'onDate'
    && normalizedRecurrenceUntil < effectiveStartDate
  ) {
    return 'invalidDateRange';
  }
  if (useEndDate && effectiveEndDate && effectiveEndDate < effectiveStartDate) {
    return 'invalidDateRange';
  }
  const isSameDayRange = !useEndDate || effectiveEndDate === effectiveStartDate;
  if (!allDay && startTime && endTime && isSameDayRange && endTime <= startTime) {
    return 'invalidTimeRange';
  }
  return null;
}
