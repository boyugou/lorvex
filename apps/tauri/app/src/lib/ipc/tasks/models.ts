import type { Task, TaskList, TaskReminder, ScheduleBlock } from '@lorvex/shared/types';

export type { Task, TaskChecklistItem, TaskList, TaskReminder, DailyReview, ScheduleBlock } from '@lorvex/shared/types';

export interface DueReminderEntry {
  task: Task;
  reminder: TaskReminder;
}

export interface ListWithCount extends TaskList {
  open_count: number;
}

export interface Stats {
  open_count: number;
  overdue_count: number;
  today_pool_count: number;
  attention_count: number;
  upcoming_week_count: number;
  completed_today: number;
  completed_this_week: number;
  completed_last_week: number;
  someday_count: number;
  completion_streak: number;
  streak_active_today: boolean;
}

interface CurrentFocusSummary {
  task_count: number;
  briefing: string | null;
  timezone: string | null;
}

export interface Overview {
  stats: Stats;
  lists: ListWithCount[];
  current_focus: CurrentFocusSummary | null;
  top_by_priority: Task[];
  recently_completed: Task[];
}

export interface CurrentFocusWithTasks {
  date: string;
  task_ids: string[];
  briefing: string | null;
  timezone: string | null;
  tasks: Task[];
}

export interface ListWithTasks {
  list: TaskList;
  tasks: Task[];
  /**
   * total count of rows matching the predicate. The
   * `tasks` array is capped at the IPC payload limit; `total_matching`
   * lets the UI surface "showing N of M — load more" when a list
   * exceeds the cap.
   */
  total_matching: number;
}

export interface FocusScheduleWithTasks {
  date: string;
  blocks: ScheduleBlock[];
  rationale: string | null;
  timezone: string | null;
  created_at: string;
  tasks: Task[];
}

export interface AttributionActor {
  kind: 'human' | 'ai';
  name: string;
}

export interface TaskAttribution {
  created_by: AttributionActor;
  deleted_by: AttributionActor | null;
  last_modified_by: AttributionActor;
}

export interface ChangelogEntry {
  id: string;
  timestamp: string;
  operation: string;
  entity_type: string;
  entity_id: string | null;
  summary: string;
  mcp_tool: string | null;
  /**
   * serialized UndoToken JSON for rows whose underlying
   * sync_outbox write is still held inside the 5-second undo window
   * AND whose token is still in the in-process cache. `null` for rows
   * past the hold, rows without an undo-eligible mutation, or after an
   * app restart (which drops the in-memory cache). Presence controls
   * rendering of the per-row Undo affordance in `ChangelogView`.
   */
  undo_token: string | null;
}

export interface StalledList {
  id: string;
  name: string;
  icon: string | null;
  color: string | null;
  open_task_count: number;
  last_activity: string;
}

export interface WeeklyReview {
  completed_this_week: Task[];
  stalled_lists: StalledList[];
  frequently_deferred: Task[];
  overdue_count: number;
  overdue_tasks: Task[];
  someday_items: Task[];
  created_this_week: number;
  completed_with_estimate_count: number;
  estimate_coverage_ratio: number | null;
  estimate_accuracy_sample_count: number;
  estimate_mean_absolute_pct_error: number | null;
}
