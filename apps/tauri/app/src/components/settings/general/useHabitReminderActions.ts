import { deleteHabitReminderPolicy, upsertHabitReminderPolicy } from '@/lib/ipc/habits';
import type { HabitReminderPolicy } from '@/lib/ipc/habits';
import { useI18n } from '@/lib/i18n';
import { defineEntityHooks } from '@/lib/query/defineEntityHooks';

/**
 * Habit reminder policies routed through `defineEntityHooks` with
 * `entity: 'habit_reminder_policy'`. The factory pairs auto
 * invalidation of `QK.habitReminderPolicies` (per the entity map) with
 * `toast.errorWithDetail` + `reportClientError` on failure — exactly
 * the surface the hand-rolled implementation duplicated.
 *
 * Pre-migration both mutations had no `onError`, so non-disk/backend
 * failures (validation, NotFound, sync conflict) were silently dropped:
 * the user toggled a habit reminder, IPC failed, the toggle flickered
 * or didn't, with no explanation. Routing through the factory makes
 * Diagnostics + toast the default for every reminder write.
 */
const habitReminderHooks = defineEntityHooks({
  entity: 'habit_reminder_policy',
  mutations: {
    upsert: {
      run: ({ id, habitId, time, enabled }: {
        id?: string;
        habitId: string;
        time: string;
        enabled?: boolean;
      }) =>
        upsertHabitReminderPolicy({
          ...(id === undefined ? {} : { id }),
          habitId,
          time,
          ...(enabled === undefined ? {} : { enabled }),
        }),
      errorContext: 'settings.habitReminder.upsert',
    },
    delete: {
      run: (id: string) => deleteHabitReminderPolicy(id),
      errorContext: 'settings.habitReminder.delete',
    },
  },
});

export function useHabitReminderActions() {
  const { t } = useI18n();

  const upsertMutation = habitReminderHooks.mutations.upsert.useMutation({
    errorMessage: t('common.error'),
  });

  const deleteMutation = habitReminderHooks.mutations.delete.useMutation({
    errorMessage: t('common.error'),
  });

  return {
    deletePending: deleteMutation.isPending,
    upsertPending: upsertMutation.isPending,
    createOrUpdateReminder: (habitId: string, time: string, enabled?: boolean) => {
      if (upsertMutation.isPending) return;
      upsertMutation.mutate(enabled === undefined ? { habitId, time } : { habitId, time, enabled });
    },
    deleteReminder: (id: string) => {
      if (deleteMutation.isPending) return;
      deleteMutation.mutate(id);
    },
    toggleReminder: (policy: HabitReminderPolicy) => {
      if (upsertMutation.isPending) return;
      upsertMutation.mutate({
        id: policy.id,
        habitId: policy.habit_id,
        time: policy.reminder_time,
        enabled: !policy.enabled,
      });
    },
  };
}
