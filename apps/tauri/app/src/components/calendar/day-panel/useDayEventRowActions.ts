import { useState, type MouseEvent } from 'react';
import { useQueryClient } from '@tanstack/react-query';

import { addEventException, deleteCalendarEvent } from '@/lib/ipc/calendar';
import type { TranslationKey } from '@/lib/i18n';
import { defineEntityHooks } from '@/lib/query/defineEntityHooks';
import { invalidateCalendarMutationQueries } from '@/lib/query/queryKeys';
import { confirm } from '@/lib/dialogs/confirm';
import { useSnapshotUndoToast } from '@/lib/hooks/useSnapshotUndoToast';

/**
 * Day-panel event row mutations routed through `defineEntityHooks`
 * with `entity: 'calendar_event'`, so delete + skip-occurrence
 * fan out to every calendar-related head via
 * `QUERY_ENTITY_INVALIDATION_MAP['calendar_event']`. The delete
 * `onSuccess` hook layers the snapshot-undo toast on top of the
 * factory's default invalidation; the row's `onInvalidate` callback
 * keeps the parent's per-day refetch in step.
 *
 * Error surface: the factory's standard path
 * (`reportClientError(errorContext, …)` + `toast.errorWithDetail`)
 * subsumes the prior `reportCalendarError` helper — `errorWithDetail`
 * already performs the disk-full / PoisonError / Utf8Error / objc2
 * pointer redaction that the legacy wrapper added on top of the toast.
 */
const dayEventRowHooks = defineEntityHooks({
  entity: 'calendar_event',
  mutations: {
    delete: {
      run: (eventId: string) => deleteCalendarEvent(eventId),
      errorContext: 'calendar.dayPanel.delete',
    },
    skipOccurrence: {
      run: ({ eventId, occurrenceDate }: { eventId: string; occurrenceDate: string }) =>
        addEventException(eventId, occurrenceDate),
      errorContext: 'calendar.dayPanel.skipOccurrence',
    },
  },
});

interface UseDayEventRowActionsArgs {
  eventId: string;
  isRecurring: boolean;
  occurrenceDate: string;
  onInvalidate: () => void;
  t: (key: TranslationKey) => string;
}

export function useDayEventRowActions({
  eventId,
  isRecurring,
  occurrenceDate,
  onInvalidate,
  t,
}: UseDayEventRowActionsArgs) {
  const queryClient = useQueryClient();
  const [confirming, setConfirming] = useState(false);
  const showSnapshotUndoToast = useSnapshotUndoToast();

  const deleteMutation = dayEventRowHooks.mutations.delete.useMutation({
    errorMessage: t('common.error'),
    onSuccess: (result) => {
      // snapshot-based undo. Surface a 5s "Undo" affordance —
      // the backend has the full pre-delete snapshot encoded in the
      // opaque token, replayed via `undoDeleteEntity` from the
      // shared hook.
      showSnapshotUndoToast({
        kind: 'calendar_event',
        token: result.undo_token,
        successKey: 'calendar.eventDeleted',
        restoredKey: 'calendar.eventRestored',
        invalidate: () => {
          invalidateCalendarMutationQueries(queryClient);
          onInvalidate();
        },
      });
      onInvalidate();
    },
  });

  const skipOccurrenceMutation = dayEventRowHooks.mutations.skipOccurrence.useMutation({
    successMessage: t('calendar.occurrenceSkipped'),
    errorMessage: t('common.error'),
    onSuccess: () => onInvalidate(),
  });

  const handleDeleteClick = (event: MouseEvent<HTMLButtonElement>) => {
    event.stopPropagation();
    setConfirming(true);
  };

  // Wrap the destructive confirm in the shared confirm() modal so
  // the second click lands on a different pointer target than the
  // initial "×". A co-located inline "Confirm" button would allow a
  // double-click to silently delete the event with no Undo.
  const handleConfirmDelete = async (event: MouseEvent<HTMLButtonElement>) => {
    event.stopPropagation();
    const ok = await confirm({
      title: t('calendar.deleteEventConfirmTitle'),
      message: t('calendar.deleteEventConfirmMessage'),
      variant: 'danger',
      confirmLabel: t('calendar.deleteEvent'),
    });
    setConfirming(false);
    if (!ok) return;
    deleteMutation.mutate(eventId);
  };

  const handleCancelDelete = (event: MouseEvent<HTMLButtonElement>) => {
    event.stopPropagation();
    setConfirming(false);
  };

  const handleSkipOccurrence = (event: MouseEvent<HTMLButtonElement>) => {
    event.stopPropagation();
    setConfirming(false);
    skipOccurrenceMutation.mutate({ eventId, occurrenceDate });
  };

  return {
    confirming,
    canSkipOccurrence: isRecurring,
    handleCancelDelete,
    handleConfirmDelete,
    handleDeleteClick,
    handleSkipOccurrence,
  };
}
