import type {
  Habit,
  HabitFrequencyType,
  HabitReminderPolicy,
  HabitSummary,
  HabitWithStats,
} from '@lorvex/shared/types';
import { invoke, invokeIpc } from './core';

// the habit types are canonical in
// @lorvex/shared. Re-export so existing frontend call sites that
// import from `../../lib/ipc/habits` keep working without knowing
// where the types live. The local HabitReminderPolicy extension
// (adding habit_name) was eliminated now that shared carries the
// optional field directly.
export type { Habit, HabitFrequencyType, HabitSummary, HabitWithStats, HabitReminderPolicy };

export interface DueHabitReminder {
  policy: HabitReminderPolicy;
}

export const getHabitReminderPolicies = (signal?: AbortSignal): Promise<HabitReminderPolicy[]> =>
  invoke('get_habit_reminder_policies', undefined, signal);

interface UpsertHabitReminderPolicyInput {
  id?: string;
  habitId: string;
  time: string;
  enabled?: boolean;
}

export const upsertHabitReminderPolicy = (
  input: UpsertHabitReminderPolicyInput,
  signal?: AbortSignal,
): Promise<HabitReminderPolicy> =>
  invokeIpc<HabitReminderPolicy>('upsert_habit_reminder_policy', {
    id: input.id ?? null,
    habit_id: input.habitId,
    reminder_time: input.time,
    enabled: input.enabled ?? true,
  }, signal);

export const deleteHabitReminderPolicy = (id: string, signal?: AbortSignal): Promise<boolean> =>
  invokeIpc<boolean>('delete_habit_reminder_policy', { id }, signal);

export const getDueHabitReminders = (signal?: AbortSignal): Promise<DueHabitReminder[]> =>
  invoke('get_due_habit_reminders', undefined, signal);

export const markHabitReminderFired = (policyId: string, signal?: AbortSignal): Promise<void> =>
  invokeIpc<void>('mark_habit_reminder_fired', { policy_id: policyId }, signal);

// ── Habit entity queries (new habit tracking system) ────────────────

export const getTodaysHabits = (signal?: AbortSignal): Promise<HabitSummary[]> =>
  invoke('get_todays_habits', undefined, signal);

export const getHabitsWithStats = (signal?: AbortSignal): Promise<HabitWithStats[]> =>
  invoke('get_habits_with_stats', undefined, signal);

export const adjustHabitCompletion = (habitId: string, delta: number, signal?: AbortSignal): Promise<HabitSummary> =>
  invokeIpc('adjust_habit_completion', { habit_id: habitId, delta }, signal);


// -- Human-UI habit writes ---------------------------
//
// Standalone users (no MCP assistant) need a way to create habits from
// the UI. These wrappers mirror the MCP `habit_create` / `habit_delete`
// tools and write through the same outbox/tombstone pipeline.

interface CreateHabitInput {
  name: string;
  icon?: string | null;
  color?: string | null;
  cue?: string | null;
  frequencyType?: HabitFrequencyType;
  /** `weekly` weekday indices, Monday-first (0=Mon … 6=Sun). */
  weekdays?: number[];
  /** `times_per_week` completions-per-week target. */
  perPeriodTarget?: number;
  /** `monthly` reminder day-of-month (1–31). */
  dayOfMonth?: number | null;
  targetCount?: number;
}

export const createHabit = (input: CreateHabitInput, signal?: AbortSignal): Promise<Habit> =>
  invokeIpc<Habit>(
    'create_habit',
    {
      name: input.name,
      icon: input.icon ?? null,
      color: input.color ?? null,
      cue: input.cue ?? null,
      frequency_type: input.frequencyType ?? null,
      weekdays: input.weekdays ?? null,
      per_period_target: input.perPeriodTarget ?? null,
      day_of_month: input.dayOfMonth ?? null,
      target_count: input.targetCount ?? null,
    },
    signal,
  );

interface DeleteHabitResult {
  deleted: boolean;
  id: string;
  name: string;
  completions_destroyed: number;
  reminder_policies_destroyed: number;
}

export const deleteHabit = (habitId: string, signal?: AbortSignal): Promise<DeleteHabitResult> =>
  invokeIpc<DeleteHabitResult>('delete_habit', { habit_id: habitId }, signal);
