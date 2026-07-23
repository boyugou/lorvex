import { invoke, invokeIpc } from '../core';

import type {
  ChangelogEntry,
  CurrentFocusWithTasks,
  DailyReview,
  Overview,
  ScheduleBlock,
  FocusScheduleWithTasks,
  Task,
  WeeklyReview,
} from './models';

export const getOverview = (signal?: AbortSignal): Promise<Overview> =>
  invoke('get_overview', undefined, signal);

export const getCurrentFocus = (signal?: AbortSignal): Promise<CurrentFocusWithTasks | null> =>
  invoke('get_current_focus', undefined, signal);

export const getFocusSchedule = (signal?: AbortSignal): Promise<FocusScheduleWithTasks | null> =>
  invoke('get_focus_schedule', undefined, signal);

// dismiss returns the post-delete aggregate state
// (always `null` after a successful clear) so the caller can refresh
// the UI without re-issuing `get_focus_schedule`. Prior shape was
// `Promise<void>`; the return is now an Option<FocusScheduleWithTasks>.
export const dismissFocusSchedule = (
  signal?: AbortSignal,
): Promise<FocusScheduleWithTasks | null> =>
  invokeIpc('dismiss_focus_schedule', {}, signal);

export const updateFocusScheduleBlocks = (
  blocks: ScheduleBlock[],
  signal?: AbortSignal,
): Promise<FocusScheduleWithTasks> =>
  invokeIpc('update_focus_schedule_blocks', { blocks }, signal);

export const getChangelog = (
  limit?: number,
  options?: { sinceIso?: string | null; sourceDeviceId?: string | null },
  signal?: AbortSignal,
): Promise<ChangelogEntry[]> =>
  invoke(
    'get_changelog',
    {
      limit: limit ?? null,
      // time-window + device-scope filters for Settings →
      // Diagnostics. Both null on non-diagnostics callers preserves the
      // previous "all rows under the limit" behavior.
      since_iso: options?.sinceIso ?? null,
      source_device_id: options?.sourceDeviceId ?? null,
    },
    signal,
  );

/**
 * revert a changelog row's underlying task mutation using
 * the 5-second undo hold. Accepts the serialized UndoToken surfaced on
 * the `ChangelogEntry.undo_token` field and delegates server-side to
 * the same `undo_task_lifecycle` pipeline used by the success-toast
 * undo buttons. Errors if the hold has already expired.
 */
export const undoChangelogEntry = (token: string, signal?: AbortSignal): Promise<Task> =>
  invokeIpc('undo_changelog_entry', { token }, signal);

/**
 * per-task History section inside TaskDetail. Returns
 * ai_changelog rows scoped to `entity_type='task' AND entity_id = :taskId`
 * so a power user can see the full audit trail of a single task without
 * hunting through the global Activity Log. The returned rows share the
 * same `ChangelogEntry` shape used by the global view so the same row
 * renderer can be reused.
 */
export const getTaskHistory = (
  taskId: string,
  limit?: number,
  signal?: AbortSignal,
): Promise<ChangelogEntry[]> =>
  invoke('get_task_history', { task_id: taskId, limit: limit ?? null }, signal);

export const getWeeklyReview = (signal?: AbortSignal): Promise<WeeklyReview> =>
  invoke('get_weekly_review', undefined, signal);

export const getDailyReviews = (limit?: number, signal?: AbortSignal): Promise<DailyReview[]> =>
  invoke('get_daily_reviews', { limit: limit ?? null }, signal);

export const getDailyReviewByDate = (date: string, signal?: AbortSignal): Promise<DailyReview | null> =>
  invoke('get_daily_review_by_date', { date }, signal);

interface UpsertDailyReviewInput {
  summary: string;
  mood: number | null;
  energy_level: number | null;
  wins: string | null;
  blockers: string | null;
  learnings: string | null;
  /**
   * YYYY-MM-DD date the review panel was showing when the user opened
   * it. Used as the UPSERT key to prevent silent misattribution across
   * local-midnight crossings (see issue).
   */
  expected_date: string;
}

export const upsertDailyReview = (input: UpsertDailyReviewInput, signal?: AbortSignal): Promise<DailyReview> =>
  invokeIpc('upsert_daily_review', { input }, signal);
