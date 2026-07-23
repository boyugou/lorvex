import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { useI18n } from '@/lib/i18n';
import { DAY_SCOPED_QUERY_KEYS } from '@/lib/query/dayScopedQueryKeys';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { getHabitReminderPolicies, getHabitsWithStats } from '@/lib/ipc/habits';
import type { HabitReminderPolicy, HabitWithStats } from '@/lib/ipc/habits';
import { confirm } from '@/lib/dialogs/confirm';
import { AppSelect } from '@/components/ui/AppSelect';
import { Toggle } from '@/components/ui/Toggle';
import { TonalButton } from '@/components/ui/TonalButton';
import { TimeInput } from '../SettingsPrimitives';
import { useHabitReminderActions } from './useHabitReminderActions';

function ReminderSlotRow({
  policy,
  deletePending,
  onDelete,
  onToggle,
  upsertPending,
}: {
  policy: HabitReminderPolicy;
  deletePending: boolean;
  onDelete: (id: string) => void;
  onToggle: (policy: HabitReminderPolicy) => void;
  upsertPending: boolean;
}) {
  const { t } = useI18n();

  return (
    <div className="flex items-center justify-between gap-3 py-1.5">
      <div className="flex items-center gap-3 min-w-0">
        <Toggle
          checked={policy.enabled}
          onChange={() => onToggle(policy)}
          disabled={upsertPending}
          ariaLabel={`${t('settings.habitReminderTime')}: ${policy.habit_name} ${policy.reminder_time}`}
        />
        <span className="text-sm text-text-primary truncate">{policy.habit_name}</span>
      </div>
      <div className="flex items-center gap-2 shrink-0">
        <span className="text-xs text-text-muted font-mono">{policy.reminder_time}</span>
        <button
          type="button"
          onClick={() => onDelete(policy.id)}
          disabled={deletePending}
          className="text-xs text-danger/70 hover:text-danger transition-colors px-1.5 py-0.5 rounded-r-control disabled:opacity-50 disabled:cursor-not-allowed focus-ring-soft-danger"
        >
          {t('common.delete')}
        </button>
      </div>
    </div>
  );
}

interface HabitReminderGroup {
  habitId: string;
  habitName: string;
  habitIcon: string | null;
  policies: HabitReminderPolicy[];
}

function HabitReminderGroupCard({
  group,
  deletePending,
  onAddSlot,
  onDelete,
  onToggle,
  upsertPending,
}: {
  group: HabitReminderGroup;
  deletePending: boolean;
  onAddSlot: (habitId: string) => void;
  onDelete: (id: string) => void;
  onToggle: (policy: HabitReminderPolicy) => void;
  upsertPending: boolean;
}) {
  const { t, format } = useI18n();
  const slotCount = group.policies.length;
  const slotLabel = slotCount === 1
    ? t('habits.singleReminder')
    : format('habits.multiReminderCount', { count: slotCount });

  return (
    <div className="rounded-r-panel border border-card bg-surface-1/80 px-3 py-3">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="flex items-center gap-2">
            {group.habitIcon && <span aria-hidden="true">{group.habitIcon}</span>}
            <span className="text-sm font-medium text-text-primary truncate">{group.habitName}</span>
          </div>
          <p className="mt-1 text-xs text-text-muted">{slotLabel}</p>
        </div>
        <button
          type="button"
          onClick={() => onAddSlot(group.habitId)}
          disabled={upsertPending}
          className="shrink-0 text-xs px-2.5 py-1 rounded-r-control bg-surface-2 border border-card text-text-secondary hover:text-text-primary hover:bg-surface-3 transition-colors disabled:opacity-50 disabled:cursor-not-allowed focus-ring-soft"
        >
          + {t('habits.addReminderSlot')}
        </button>
      </div>

      <div className="mt-2 space-y-1">
        {group.policies.map((policy) => (
          <ReminderSlotRow
            key={policy.id}
            policy={policy}
            deletePending={deletePending}
            onDelete={onDelete}
            onToggle={onToggle}
            upsertPending={upsertPending}
          />
        ))}
      </div>
    </div>
  );
}

/** Inner content without the wrapping SettingsSection — used when the parent controls collapse. */
export function HabitRemindersPanelContent() {
  const { t } = useI18n();
  const { todayYmd } = useConfiguredDayContext();
  const [adding, setAdding] = useState(false);
  const [selectedHabitId, setSelectedHabitId] = useState('');
  const [newTime, setNewTime] = useState('08:00');
  const {
    createOrUpdateReminder,
    deletePending,
    deleteReminder,
    toggleReminder,
    upsertPending,
  } = useHabitReminderActions();

  const { data: policies = [] } = useQuery({
    queryKey: QUERY_KEYS.habitReminderPolicies(),
    queryFn: ({ signal }) => getHabitReminderPolicies(signal),
  });

  const { data: habits = [] } = useQuery({
    queryKey: DAY_SCOPED_QUERY_KEYS.habitsWithStats(todayYmd),
    queryFn: ({ signal }) => getHabitsWithStats(signal),
  });

  const habitsById = useMemo(() => {
    const map = new Map<string, HabitWithStats>();
    for (const habit of habits) {
      map.set(habit.id, habit);
    }
    return map;
  }, [habits]);

  const reminderGroups = useMemo<HabitReminderGroup[]>(() => {
    const groups = new Map<string, HabitReminderGroup>();
    for (const policy of policies) {
      const existing = groups.get(policy.habit_id);
      if (existing) {
        existing.policies.push(policy);
        continue;
      }
      const habit = habitsById.get(policy.habit_id);
      groups.set(policy.habit_id, {
        habitId: policy.habit_id,
        habitName: habit?.name ?? policy.habit_name ?? '',
        habitIcon: habit?.icon ?? null,
        policies: [policy],
      });
    }
    return Array.from(groups.values())
      .map((group) => ({
        ...group,
        policies: [...group.policies].sort((a, b) => a.reminder_time.localeCompare(b.reminder_time)),
      }))
      .sort((a, b) => a.habitName.localeCompare(b.habitName));
  }, [habitsById, policies]);

  const availableHabits = useMemo(
    () => [...habits].sort((a, b) => a.name.localeCompare(b.name)),
    [habits],
  );

  const handleAdd = () => {
    if (!selectedHabitId) return;
    createOrUpdateReminder(selectedHabitId, newTime);
    setSelectedHabitId('');
    setNewTime('08:00');
    setAdding(false);
  };

  const handleToggle = (policy: HabitReminderPolicy) => {
    toggleReminder(policy);
  };

  const handleDelete = async (id: string) => {
    const ok = await confirm({
      title: t('habits.deleteReminderTitle'),
      message: t('habits.deleteReminderConfirm'),
      confirmLabel: t('common.delete'),
      variant: 'danger',
    });
    if (!ok) return;
    deleteReminder(id);
  };

  const beginAddReminder = (habitId?: string) => {
    setSelectedHabitId(habitId ?? '');
    setNewTime('08:00');
    setAdding(true);
  };

  return (
    <>
      {policies.length === 0 && !adding && (
        <p className="text-xs text-text-muted">{t('habits.empty')}</p>
      )}

      {reminderGroups.length > 0 && (
        <div className="space-y-2">
          {reminderGroups.map((group) => (
            <HabitReminderGroupCard
              key={group.habitId}
              group={group}
              deletePending={deletePending}
              onAddSlot={beginAddReminder}
              onDelete={(id) => { void handleDelete(id); }}
              onToggle={handleToggle}
              upsertPending={upsertPending}
            />
          ))}
        </div>
      )}

      {adding ? (
        <div className="mt-2 space-y-2">
          <AppSelect
            value={selectedHabitId}
            variant="default"
            onChange={(e) => setSelectedHabitId(e.target.value)}
            aria-label={t('habits.addReminder')}
            className="w-full"
          >
            <option value="">{t('habits.habitName')}</option>
            {availableHabits.map((h) => (
              <option key={h.id} value={h.id}>
                {h.icon ? `${h.icon} ` : ''}{h.name}
              </option>
            ))}
          </AppSelect>
          <div className="flex items-center gap-3">
            <TimeInput
              value={newTime}
              onChange={setNewTime}
              ariaLabel={t('settings.habitReminderTime')}
            />
            <TonalButton
              tone="accent"
              fill="soft"
              size="lg"
              onClick={handleAdd}
              disabled={!selectedHabitId || upsertPending}
            >
              {t('common.save')}
            </TonalButton>
            <button
              type="button"
              onClick={() => setAdding(false)}
              className="text-xs px-3 py-1.5 rounded-r-control bg-surface-1 border border-surface-3 text-text-secondary hover:bg-surface-3 transition-colors focus-ring-soft"
            >
              {t('common.cancel')}
            </button>
          </div>
        </div>
      ) : (
        <button
          type="button"
          onClick={() => beginAddReminder()}
          disabled={upsertPending}
          className="mt-2 text-xs text-accent hover:text-accent/80 transition-colors disabled:opacity-50 disabled:cursor-not-allowed focus-ring-soft"
        >
          + {t('habits.addReminder')}
        </button>
      )}
    </>
  );
}
