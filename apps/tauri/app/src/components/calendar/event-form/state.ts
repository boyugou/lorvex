import {
  useMemo,
  useRef,
  useState,
  type Dispatch,
  type RefObject,
  type SetStateAction,
} from 'react';

import type { CalendarRecurrenceEndCondition, CalendarRecurrencePreset, WeekdayCode } from '../calendarViewUtils';
import {
  recurrenceFromRaw,
  recurrencePresetToRaw,
} from '../calendarViewUtils';
import { EVENT_COLORS } from '../viewSupport';
import {
  getSystemTimezone,
  isValidTimezone,
  normalizeTimezonePreference,
  resolveTimezoneOptions,
} from '@/lib/dates/timezone';
import type { EventFormControllerInput } from './support';

export interface EventFormState {
  titleRef: RefObject<HTMLInputElement | null>;
  isEditing: boolean;
  title: string;
  setTitle: Dispatch<SetStateAction<string>>;
  startDate: string;
  setStartDate: Dispatch<SetStateAction<string>>;
  useEndDate: boolean;
  setUseEndDate: Dispatch<SetStateAction<boolean>>;
  endDate: string;
  setEndDate: Dispatch<SetStateAction<string>>;
  startTime: string;
  setStartTime: Dispatch<SetStateAction<string>>;
  endTime: string;
  setEndTime: Dispatch<SetStateAction<string>>;
  allDay: boolean;
  setAllDay: Dispatch<SetStateAction<boolean>>;
  recurrencePreset: CalendarRecurrencePreset;
  setRecurrencePreset: Dispatch<SetStateAction<CalendarRecurrencePreset>>;
  recurrenceInterval: number;
  setRecurrenceInterval: Dispatch<SetStateAction<number>>;
  recurrenceWeekdays: WeekdayCode[];
  setRecurrenceWeekdays: Dispatch<SetStateAction<WeekdayCode[]>>;
  recurrenceEndCondition: CalendarRecurrenceEndCondition;
  setRecurrenceEndCondition: Dispatch<SetStateAction<CalendarRecurrenceEndCondition>>;
  recurrenceUntilDate: string;
  setRecurrenceUntilDate: Dispatch<SetStateAction<string>>;
  location: string;
  setLocation: Dispatch<SetStateAction<string>>;
  description: string;
  setDescription: Dispatch<SetStateAction<string>>;
  timezone: string;
  setTimezone: Dispatch<SetStateAction<string>>;
  timezoneWasEditedRef: RefObject<boolean>;
  systemTimezone: string;
  hasEventTimezone: boolean;
  normalizedTimezone: string;
  timezoneOptions: string[];
  color: string;
  setColor: Dispatch<SetStateAction<string>>;
  effectiveStartDate: string;
  normalizedRecurrenceUntil: string;
  recurrenceRaw: string | null;
  effectiveEndDate: string | null;
}

export function useEventFormState({
  date,
  event,
}: Pick<EventFormControllerInput, 'date' | 'event'>): EventFormState {
  const isEditing = event !== null;
  const titleRef = useRef<HTMLInputElement>(null);
  const initialStartDate = event?.start_date ?? date;
  const initialEndDate = event?.end_date ?? initialStartDate;
  const initialUseEndDate = Boolean(event?.end_date && event.end_date !== initialStartDate);
  const initialRecurrence = recurrenceFromRaw(event?.recurrence ?? null, initialStartDate);
  const preservedAdvancedRecurrence = initialRecurrence.preset === 'advanced' ? event?.recurrence ?? null : null;

  const [title, setTitle] = useState(event?.title ?? '');
  const [startDate, setStartDate] = useState(initialStartDate);
  const [useEndDate, setUseEndDate] = useState(initialUseEndDate);
  const [endDate, setEndDate] = useState(initialEndDate);
  const [startTime, setStartTime] = useState(event?.start_time ?? '');
  const [endTime, setEndTime] = useState(event?.end_time ?? '');
  const [allDay, setAllDay] = useState(event ? event.all_day : false);
  const [recurrencePreset, setRecurrencePreset] = useState<CalendarRecurrencePreset>(initialRecurrence.preset);
  const [recurrenceInterval, setRecurrenceInterval] = useState(initialRecurrence.interval);
  const [recurrenceWeekdays, setRecurrenceWeekdays] = useState<WeekdayCode[]>(initialRecurrence.byday);
  const [recurrenceEndCondition, setRecurrenceEndCondition] = useState<CalendarRecurrenceEndCondition>(
    initialRecurrence.endCondition,
  );
  const [recurrenceUntilDate, setRecurrenceUntilDate] = useState(initialRecurrence.until || initialStartDate);
  const [location, setLocation] = useState(event?.location ?? '');
  const [description, setDescription] = useState(event?.description ?? '');
  const systemTimezone = getSystemTimezone();
  const hasEventTimezone = isValidTimezone(event?.timezone);
  const [timezone, setTimezone] = useState(() => normalizeTimezonePreference(event?.timezone, systemTimezone));
  const timezoneWasEditedRef = useRef(false);
  const normalizedTimezone = useMemo(
    () => normalizeTimezonePreference(timezone, systemTimezone),
    [timezone, systemTimezone],
  );
  const timezoneOptions = useMemo(
    () => resolveTimezoneOptions(normalizedTimezone, systemTimezone),
    [normalizedTimezone, systemTimezone],
  );
  const [color, setColor] = useState(event?.color ?? EVENT_COLORS[0]!);

  const effectiveStartDate = startDate || date;
  const normalizedRecurrenceUntil = recurrenceEndCondition === 'onDate'
    ? (recurrenceUntilDate || effectiveStartDate)
    : '';
  const recurrenceRaw = recurrencePreset === 'advanced'
    ? preservedAdvancedRecurrence
    : recurrencePresetToRaw(
        recurrencePreset,
        recurrenceInterval,
        recurrenceWeekdays,
        recurrenceEndCondition,
        normalizedRecurrenceUntil,
        effectiveStartDate,
      );
  const effectiveEndDate = useEndDate ? (endDate || effectiveStartDate) : null;

  return {
    titleRef,
    isEditing,
    title,
    setTitle,
    startDate,
    setStartDate,
    useEndDate,
    setUseEndDate,
    endDate,
    setEndDate,
    startTime,
    setStartTime,
    endTime,
    setEndTime,
    allDay,
    setAllDay,
    recurrencePreset,
    setRecurrencePreset,
    recurrenceInterval,
    setRecurrenceInterval,
    recurrenceWeekdays,
    setRecurrenceWeekdays,
    recurrenceEndCondition,
    setRecurrenceEndCondition,
    recurrenceUntilDate,
    setRecurrenceUntilDate,
    location,
    setLocation,
    description,
    setDescription,
    timezone,
    setTimezone,
    timezoneWasEditedRef,
    systemTimezone,
    hasEventTimezone,
    normalizedTimezone,
    timezoneOptions,
    color,
    setColor,
    effectiveStartDate,
    normalizedRecurrenceUntil,
    recurrenceRaw,
    effectiveEndDate,
  };
}
