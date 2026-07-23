import { useEventFormEffects } from './effects';
import { useEventFormMutations } from './mutations';
import { type EventFormControllerInput } from './support';
import { useEventFormState } from './state';

export function useEventFormController({
  date,
  event,
  t,
  onDone,
}: EventFormControllerInput) {
  const state = useEventFormState({ date, event });

  useEventFormEffects({
    date,
    eventTimezone: event?.timezone,
    state,
  });

  const mutations = useEventFormMutations({
    date,
    event,
    t,
    onDone,
    state,
  });

  return {
    titleRef: state.titleRef,
    isEditing: state.isEditing,
    title: state.title,
    setTitle: state.setTitle,
    startDate: state.startDate,
    handleStartDateChange: mutations.handleStartDateChange,
    useEndDate: state.useEndDate,
    handleUseEndDateChange: mutations.handleUseEndDateChange,
    endDate: state.endDate,
    setEndDate: state.setEndDate,
    startTime: state.startTime,
    setStartTime: state.setStartTime,
    endTime: state.endTime,
    setEndTime: state.setEndTime,
    allDay: state.allDay,
    setAllDay: state.setAllDay,
    normalizedTimezone: state.normalizedTimezone,
    timezoneOptions: state.timezoneOptions,
    handleTimezoneChange: mutations.handleTimezoneChange,
    recurrencePreset: state.recurrencePreset,
    handleRecurrencePresetChange: mutations.handleRecurrencePresetChange,
    recurrenceInterval: state.recurrenceInterval,
    handleRecurrenceIntervalChange: mutations.handleRecurrenceIntervalChange,
    recurrenceEndCondition: state.recurrenceEndCondition,
    handleRecurrenceEndConditionChange: mutations.handleRecurrenceEndConditionChange,
    normalizedRecurrenceUntil: state.normalizedRecurrenceUntil,
    setRecurrenceUntilDate: state.setRecurrenceUntilDate,
    recurrenceWeekdays: state.recurrenceWeekdays,
    toggleRecurrenceWeekday: mutations.toggleRecurrenceWeekday,
    effectiveStartDate: state.effectiveStartDate,
    location: state.location,
    setLocation: state.setLocation,
    description: state.description,
    setDescription: state.setDescription,
    color: state.color,
    setColor: state.setColor,
    isDeleting: mutations.isDeleting,
    isSaving: mutations.isSaving,
    handleDelete: mutations.handleDelete,
    handleSubmit: mutations.handleSubmit,
  };
}
