import { useState, type FormEvent } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { applyScopedCalendarEventEdit, createCalendarEvent, deleteCalendarEvent, deleteScopedCalendarEvent, updateCalendarEvent } from '@/lib/ipc/calendar';
import { useI18n } from '@/lib/i18n';
import { defineEntityHooks } from '@/lib/query/defineEntityHooks';
import { invalidateCalendarMutationQueries, QK, QUERY_KEYS } from '@/lib/query/queryKeys';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import { toast } from '@/lib/notifications/toast';
import { confirm } from '@/lib/dialogs/confirm';
import { useSnapshotUndoToast } from '@/lib/hooks/useSnapshotUndoToast';
import { convertWallTime } from '@/lib/dates/timezone';
import type { CalendarRecurrenceEndCondition, CalendarRecurrencePreset, WeekdayCode } from '../calendarViewUtils';
import { WEEKDAY_ORDER } from '../calendarViewUtils';
import { reportCalendarError } from '../viewSupport';
import type { EventFormControllerInput } from './support';
import { buildErrorContext, buildEventPayload, validateEventSubmission } from './support';
import type { EventFormState } from './state';
import { normalizeRecurrenceIntervalInput } from './mutations.logic';
import { pickRecurrenceScope, type RecurrenceScope } from './recurrenceScope';

/**
 * Event-form CRUD routed through `defineEntityHooks` with
 * `entity: 'calendar_event'`. The factory pairs auto invalidation of
 * every calendar head via
 * `QUERY_ENTITY_INVALIDATION_MAP['calendar_event']` with
 * `reportClientError`-keyed error logs; per-mutation `onSuccess`
 * hooks below layer the snapshot-undo toast (delete) and the
 * post-success cleanup (create/update) on top.
 *
 * The form-level `applyScopedEdit` / scoped-delete branches stay on
 * raw `await` against the IPC because the workflow returns a
 * composite result the factory cannot express; their
 * `scopedSavingCount` / `scopedDeletingCount` counters substitute for
 * `mutation.isPending`. Those bespoke branches surface their own
 * error via `reportCalendarError` to keep the IPC-level redaction
 * the factory's auto path would otherwise own.
 */
type CreateInput = { payload: ReturnType<typeof buildEventPayload> };
type UpdateInput = { id: string; payload: ReturnType<typeof buildEventPayload> };

const eventFormHooks = defineEntityHooks({
  entity: 'calendar_event',
  mutations: {
    create: {
      run: ({ payload }: CreateInput) => createCalendarEvent(payload),
      errorContext: 'calendar.eventForm.create',
    },
    update: {
      run: ({ id, payload }: UpdateInput) => updateCalendarEvent(id, payload),
      errorContext: 'calendar.eventForm.update',
    },
    delete: {
      run: (id: string) => deleteCalendarEvent(id),
      errorContext: 'calendar.eventForm.delete',
    },
  },
});

interface UseEventFormMutationsArgs extends EventFormControllerInput {
  state: Pick<
    EventFormState,
    | 'isEditing'
    | 'title'
    | 'setStartDate'
    | 'startDate'
    | 'useEndDate'
    | 'setUseEndDate'
    | 'endDate'
    | 'setEndDate'
    | 'allDay'
    | 'startTime'
    | 'setStartTime'
    | 'endTime'
    | 'setEndTime'
    | 'normalizedTimezone'
    | 'setTimezone'
    | 'timezoneWasEditedRef'
    | 'recurrencePreset'
    | 'setRecurrencePreset'
    | 'recurrenceInterval'
    | 'setRecurrenceInterval'
    | 'recurrenceEndCondition'
    | 'setRecurrenceEndCondition'
    | 'normalizedRecurrenceUntil'
    | 'setRecurrenceUntilDate'
    | 'recurrenceWeekdays'
    | 'setRecurrenceWeekdays'
    | 'effectiveStartDate'
    | 'location'
    | 'description'
    | 'color'
    | 'recurrenceRaw'
    | 'effectiveEndDate'
  >;
}

export function useEventFormMutations({
  date,
  event,
  onDone,
  state,
  t,
}: UseEventFormMutationsArgs) {
  const qc = useQueryClient();
  const showSnapshotUndoToast = useSnapshotUndoToast();
  const { format } = useI18n();
  // the scoped (`thisOnly` / `thisAndFollowing`) edit + delete
  // paths use raw `await` against IPC instead of `useMutation`, so the
  // `createMut.isPending` / `deleteMut.isPending` flags below stay
  // false for the scoped operation. Without this counter the Save /
  // Delete buttons re-enable mid-flight and an Enter-press can
  // dispatch a duplicate backend workflow call.
  const [scopedSavingCount, setScopedSavingCount] = useState(0);
  const [scopedDeletingCount, setScopedDeletingCount] = useState(0);
  const beginScopedSave = () => setScopedSavingCount((n) => n + 1);
  const endScopedSave = () => setScopedSavingCount((n) => Math.max(0, n - 1));
  const beginScopedDelete = () => setScopedDeletingCount((n) => n + 1);
  const endScopedDelete = () => setScopedDeletingCount((n) => Math.max(0, n - 1));
  const {
    allDay,
    color,
    description,
    effectiveEndDate,
    effectiveStartDate,
    endDate,
    endTime,
    isEditing,
    location,
    normalizedRecurrenceUntil,
    normalizedTimezone,
    recurrenceEndCondition,
    recurrencePreset,
    recurrenceRaw,
    setEndDate,
    setRecurrenceEndCondition,
    setRecurrenceInterval,
    setRecurrencePreset,
    setRecurrenceUntilDate,
    setRecurrenceWeekdays,
    setEndTime,
    setStartDate,
    setStartTime,
    setTimezone,
    setUseEndDate,
    startDate,
    startTime,
    title,
    timezoneWasEditedRef,
    useEndDate,
  } = state;

  const submissionState = {
    title,
    effectiveStartDate,
    allDay,
    startTime,
    endTime,
    effectiveEndDate,
    recurrenceRaw,
    normalizedTimezone,
    location,
    description,
    color,
    isEditing,
  };

  const invalidateCalendar = () => {
    invalidateCalendarMutationQueries(qc);
  };

  const createMut = eventFormHooks.mutations.create.useMutation({
    successMessage: t('calendar.eventCreated'),
    errorMessage: t('common.error'),
    onSuccess: () => onDone(),
  });

  const updateMut = eventFormHooks.mutations.update.useMutation({
    successMessage: t('calendar.eventUpdated'),
    errorMessage: t('common.error'),
    onSuccess: () => onDone(),
  });

  const deleteMut = eventFormHooks.mutations.delete.useMutation({
    errorMessage: t('common.error'),
    onSuccess: (result) => {
      // snapshot-based undo for non-task entities. The
      // backend captured a full pre-delete snapshot of the event
      // row + linked task ids; clicking Undo within ~5s replays it
      // back into the canonical write path via the shared hook.
      showSnapshotUndoToast({
        kind: 'calendar_event',
        token: result.undo_token,
        successKey: 'calendar.eventDeleted',
        restoredKey: 'calendar.eventRestored',
        invalidate: () => {
          invalidateCalendar();
        },
      });
      onDone();
    },
  });

  const handleStartDateChange = (next: string) => {
    const normalized = next || date;
    setStartDate(next);
    if (!useEndDate) setEndDate(normalized);
  };

  const handleUseEndDateChange = (enabled: boolean) => {
    const fallbackDate = startDate || date;
    setUseEndDate(enabled);
    if (!enabled) setEndDate(fallbackDate);
    else if (!endDate) setEndDate(fallbackDate);
  };

  const handleTimezoneChange = async (next: string) => {
    const previousTimezone = normalizedTimezone;
    timezoneWasEditedRef.current = true;
    setTimezone(next);
    // when the user has already entered a wall-clock time, ask
    // whether they meant the time as anchored to the OLD zone (and we
    // should re-render it in the NEW zone — "Convert") or as
    // free-floating local time that should keep its digits ("Keep
    // absolute"). Skip the dialog for all-day events (no times to
    // convert), no-op zone changes, and rows where neither time is set.
    if (allDay) return;
    if (!previousTimezone || previousTimezone === next) return;
    if (!startTime && !endTime) return;
    // Route through `format()` so the placeholder substitution
    // matches the i18n contract used everywhere else in this file
    // and sits inside the locale parity audit.
    const description = format('calendar.timezoneChangeConfirm.description', {
      oldTz: previousTimezone,
      newTz: next,
    });
    const shouldConvert = await confirm({
      title: t('calendar.timezoneChangeConfirm.title'),
      message: description,
      confirmLabel: t('calendar.timezoneChangeConfirm.convert'),
      cancelLabel: t('calendar.timezoneChangeConfirm.keep'),
      // "Convert" is the safe default for almost every user — it
      // preserves the absolute moment in time. Focus the primary
      // button so a quick Enter completes the expected path. ("Keep
      // absolute" is a power-user escape hatch for cases like
      // re-anchoring a recurring local-time entry to a new home zone.)
      focusPrimary: true,
    });
    if (!shouldConvert) return;
    // Convert each populated time independently. The conversion can
    // shift the calendar date (e.g. 23:00 NY → 04:00+1 UTC), so we
    // also patch the matching date field. The end-date patch only
    // happens when the form is in single-day mode AND the user hasn't
    // explicitly toggled `useEndDate` — keeping multi-day spans intact
    // on the user's terms.
    if (startTime) {
      const converted = convertWallTime(
        { date: startDate || date, time: startTime },
        previousTimezone,
        next,
      );
      if (converted) {
        setStartTime(converted.time);
        setStartDate(converted.date);
        if (!useEndDate) setEndDate(converted.date);
      }
    }
    if (endTime) {
      const baseEndDate = useEndDate ? (endDate || startDate || date) : (startDate || date);
      const converted = convertWallTime(
        { date: baseEndDate, time: endTime },
        previousTimezone,
        next,
      );
      if (converted) {
        setEndTime(converted.time);
        if (useEndDate) setEndDate(converted.date);
      }
    }
  };

  const handleRecurrencePresetChange = (next: string) => {
    setRecurrencePreset(next as CalendarRecurrencePreset);
  };

  const handleRecurrenceIntervalChange = (raw: string) => {
    setRecurrenceInterval(normalizeRecurrenceIntervalInput(raw));
  };

  const handleRecurrenceEndConditionChange = (next: string) => {
    const value = next as CalendarRecurrenceEndCondition;
    setRecurrenceEndCondition(value);
    if (value === 'onDate' && !state.normalizedRecurrenceUntil) {
      setRecurrenceUntilDate(effectiveStartDate);
    }
  };

  const toggleRecurrenceWeekday = (code: WeekdayCode) => {
    setRecurrenceWeekdays((previous) => {
      if (previous.includes(code)) {
        return previous.length > 1 ? previous.filter((current) => current !== code) : previous;
      }
      return WEEKDAY_ORDER.filter((current) => [...previous, code].includes(current));
    });
  };

  // Apply an edit to a recurring event according to the user's scope choice.
  // The scoped branches are a single backend workflow call so the
  // exception/replacement/truncation steps commit or roll back together.
  const applyScopedEdit = async (scope: RecurrenceScope) => {
    if (!event) return;
    // guard against a duplicate scoped dispatch (Enter-while-
    // in-flight / double-click). `allInSeries` already routes through
    // `updateMut.mutate` whose `isPending` flag the form button uses.
    //
    // D7: this is a defensive silent-abort. The Save button
    // visually disables while `isSaving` is true (see `useEventFormController`
    // — the `isSaving` selector covers `scopedSavingCount > 0`), so a
    // user-initiated double-click should never reach this branch.
    // Programmatic dispatch (Enter on a focused input while the
    // disabled button cannot receive the click) is the actual
    // attack surface. We deliberately do not surface a toast here:
    // the in-flight save is about to fire its own success/error
    // toast, and adding a "you double-clicked" message would add
    // noise without informing user action.
    if (scopedSavingCount > 0) return;
    const payload = buildEventPayload(submissionState);
    if (scope === 'allInSeries') {
      if (!event) return;
      updateMut.mutate({ id: event.id, payload });
      return;
    }
    beginScopedSave();
    try {
      const result = await applyScopedCalendarEventEdit({
        id: event.id,
        occurrence_date: date,
        scope,
        payload,
      });
      if (result.noop) {
        toast.info(t('calendar.nothingToTruncate'));
        onDone();
        return;
      }
      invalidateCalendar();
      if (result.delete_result && result.replacement_event) {
        // the collapse branch deleted the original AND created
        // a replacement. A snapshot-undo restores ONLY the deleted
        // original — without `onAfterUndo` cleanup the user would
        // end up with two overlapping series. Capture the new event's
        // id and remove it as part of the restore.
        const replacementId = result.replacement_event.id;
        showSnapshotUndoToast({
          kind: 'calendar_event',
          token: result.delete_result.undo_token,
          // D4+D8: collapse the visible discriminator. The Undo
          // button itself is the affordance — the user doesn't need a
          // distinct "replaced" copy versus "updated", and the cycle-9
          // wording drift made the surface inconsistent with the
          // truncated branch that already says "Event updated".
          successKey: 'calendar.eventUpdated',
          restoredKey: 'calendar.eventRestored',
          invalidate: () => {
            invalidateCalendar();
          },
          onAfterUndo: async () => {
            // optimistically remove the replacement from every
            // cached calendar-events query BEFORE awaiting the IPC.
            // Without this, the snapshot restore lands the original
            // back in the cache while the replacement is still
            // present, producing a duplicate-row flicker visible for
            // the entire round-trip of `deleteCalendarEvent`. By
            // mutating the cache first the user sees only the
            // restored original; the IPC catches up in the
            // background. If the IPC fails, the surrounding
            // `useSnapshotUndoToast` catch path re-invalidates so a
            // refetch restores the (still-existing) replacement to
            // the cache and the user can act on it manually.
            qc.setQueriesData<UnifiedCalendarEvent[]>(
              { queryKey: QUERY_KEYS.head(QK.calendarEvents) },
              (prev) =>
                prev ? prev.filter((evt) => evt.id !== replacementId) : prev,
            );
            try {
              await deleteCalendarEvent(replacementId);
              invalidateCalendar();
            } catch (err) {
              // Re-invalidate so a refetch reconciles the cache with
              // server truth (the replacement still exists). The
              // hook's onAfterUndo failure path already surfaces a
              // user-facing warning and `reportClientError`,
              // so we just need to make sure the next render shows
              // the orphan again instead of the optimistic ghost.
              invalidateCalendar();
              throw err;
            }
          },
        });
      } else {
        toast.success(t('calendar.eventUpdated'));
      }
      onDone();
    } catch (error) {
      reportCalendarError('update', error, t, buildErrorContext(submissionState));
    } finally {
      endScopedSave();
    }
  };

  const handleSubmit = async (event_: FormEvent) => {
    event_.preventDefault();
    // The Save button visually disables while a mutation is in flight,
    // but pressing Enter inside any text field still fires submit on a
    // disabled button — guard explicitly so a slow round-trip cannot
    // produce duplicate calendar events ( H3).
    // also gate on the scoped-save counter so an Enter-press
    // mid-flight on a recurring edit cannot dispatch a duplicate
    // scoped op (the scoped paths bypass `useMutation`'s `isPending`).
    if (createMut.isPending || updateMut.isPending || scopedSavingCount > 0) return;
    const validationError = validateEventSubmission({
      title,
      effectiveStartDate,
      recurrencePreset,
      recurrenceEndCondition,
      normalizedRecurrenceUntil,
      useEndDate,
      effectiveEndDate,
      allDay,
      startTime,
      endTime,
    });
    if (validationError === 'missingTitle') return;
    if (validationError === 'missingStartDate') {
      toast.error(t('calendar.missingStartDate'));
      return;
    }
    if (validationError === 'invalidDateRange') {
      toast.error(t('calendar.invalidDateRange'));
      return;
    }
    if (validationError === 'invalidTimeRange') {
      toast.error(t('calendar.invalidTimeRange'));
      return;
    }
    if (!isEditing) {
      createMut.mutate({ payload: buildEventPayload(submissionState) });
      return;
    }
    // Editing: if the underlying event is recurring, prompt the user
    // for the scope. Non-recurring events keep the silent whole-record
    // update path because there is nothing to choose between.
    if (event && event.recurrence) {
      const scope = await pickRecurrenceScope({ mode: 'edit' });
      if (!scope) return;
      await applyScopedEdit(scope);
      return;
    }
    if (!event) return;
    updateMut.mutate({ id: event.id, payload: buildEventPayload(submissionState) });
  };

  return {
    handleStartDateChange,
    handleUseEndDateChange,
    handleTimezoneChange,
    handleRecurrencePresetChange,
    handleRecurrenceIntervalChange,
    handleRecurrenceEndConditionChange,
    toggleRecurrenceWeekday,
    handleSubmit,
    // Route calendar event deletion through the shared confirm()
    // modal that every other destructive action uses. An inline
    // two-click pattern that swapped Delete for a Confirm button at
    // the same screen position would silently delete the event with
    // no Undo on a double-click. Using the app-wide modal also keeps
    // the vocabulary consistent with task / list / memory /
    // changelog deletion flows.
    handleDelete: async () => {
      // same in-flight guard as the edit path. Without it a
      // double-tap on Delete (or Enter while the modal is settling)
      // can dispatch two scoped deletes in succession.
      //
      // D7: see the matching comment in `applyScopedEdit` for
      // why this defensive silent-abort doesn't surface a toast.
      if (scopedDeletingCount > 0) return;
      // Recurring events route through the 3-way scope picker
      //. Non-recurring events keep the existing single-confirm
      // flow — the picker would only ever offer one viable option.
      if (event && event.recurrence) {
        const scope = await pickRecurrenceScope({ mode: 'delete' });
        if (!scope) return;
        if (scope === 'allInSeries') {
          deleteMut.mutate(event.id);
          return;
        }
        beginScopedDelete();
        try {
          const result = await deleteScopedCalendarEvent({
            id: event.id,
            occurrence_date: date,
            scope,
          });
          if (result.noop) {
            toast.info(t('calendar.nothingToTruncate'));
            onDone();
            return;
          }
          invalidateCalendar();
          if (result.delete_result) {
            showSnapshotUndoToast({
              kind: 'calendar_event',
              token: result.delete_result.undo_token,
              successKey: 'calendar.eventDeleted',
              restoredKey: 'calendar.eventRestored',
              invalidate: () => {
                invalidateCalendar();
              },
            });
          } else {
            toast.success(t('calendar.eventDeleted'));
          }
          onDone();
        } catch (error) {
          reportCalendarError('delete', error, t);
        } finally {
          endScopedDelete();
        }
        return;
      }
      const ok = await confirm({
        title: t('calendar.deleteEventConfirmTitle'),
        message: t('calendar.deleteEventConfirmMessage'),
        variant: 'danger',
        confirmLabel: t('calendar.deleteEvent'),
      });
      if (!ok) return;
      if (!event) return;
      deleteMut.mutate(event.id);
    },
    isDeleting: deleteMut.isPending || scopedDeletingCount > 0,
    isSaving: createMut.isPending || updateMut.isPending || scopedSavingCount > 0,
  };
}
