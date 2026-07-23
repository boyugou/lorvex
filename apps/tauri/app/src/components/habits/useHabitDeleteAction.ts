import { useCallback } from 'react';

import { confirm } from '@/lib/dialogs/confirm';
import { useI18n } from '@/lib/i18n';
import { deleteHabit } from '@/lib/ipc/habits';
import type { HabitWithStats } from '@/lib/ipc/habits';
import { defineEntityHooks } from '@/lib/query/defineEntityHooks';

const habitHooks = defineEntityHooks({
  entity: 'habit',
  mutations: {
    delete: {
      run: (habitId: string) => deleteHabit(habitId),
      errorContext: 'delete_habit',
    },
  },
});

export function useHabitDeleteAction() {
  const { t, format } = useI18n();
  const deleteMutation = habitHooks.mutations.delete.useMutation({
    successMessage: t('habits.deleteHabitSuccess'),
    errorMessage: t('habits.deleteHabitFailed'),
  });

  return useCallback(
    (habit: HabitWithStats, triggerElement: HTMLElement | null) => {
      void (async () => {
        const confirmed = await confirm({
          title: t('habits.deleteHabitTitle'),
          message: format('habits.deleteHabitConfirm', { name: habit.name }),
          confirmLabel: t('common.delete'),
          variant: 'danger',
          triggerElement,
        });
        if (!confirmed) return;
        deleteMutation.mutate(habit.id);
      })();
    },
    [deleteMutation, t, format],
  );
}
