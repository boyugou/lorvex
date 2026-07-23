import type { Task } from '@/lib/ipc/tasks/models';
import { taskEffectiveActionDate } from './dayBuckets';

/** Stable title comparator with deterministic ID fallback. */
export function compareTaskIdentity(a: Task, b: Task): number {
  const titleCompare = a.title.localeCompare(b.title);
  if (titleCompare !== 0) return titleCompare;
  return a.id.localeCompare(b.id);
}

/** Canonical deterministic tiebreaker for non-title task sorts. */
export function compareTaskId(a: Task, b: Task): number {
  return a.id.localeCompare(b.id);
}

function compareTaskPriority(a: Task, b: Task): number {
  return (a.priority ?? 4) - (b.priority ?? 4);
}

function compareNullableTextNullsLast(a: string | null | undefined, b: string | null | undefined): number {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.localeCompare(b);
}

/** Sort by the canonical Rust planning order: priority, then due date, then identity. */
export function compareTaskByPriorityThenDue(a: Task, b: Task): number {
  const priorityCompare = compareTaskPriority(a, b);
  if (priorityCompare !== 0) return priorityCompare;
  const dueDateCompare = compareNullableTextNullsLast(a.due_date, b.due_date);
  if (dueDateCompare !== 0) return dueDateCompare;
  return compareTaskId(a, b);
}

/** Sort oldest deadline risk first, then importance, then identity. */
export function compareTaskByDueThenPriority(a: Task, b: Task): number {
  const dueDateCompare = compareNullableTextNullsLast(a.due_date, b.due_date);
  if (dueDateCompare !== 0) return dueDateCompare;
  const timeCompare = compareNullableTextNullsLast(a.due_time, b.due_time);
  if (timeCompare !== 0) return timeCompare;
  const priorityCompare = compareTaskPriority(a, b);
  if (priorityCompare !== 0) return priorityCompare;
  return compareTaskId(a, b);
}

/** Sort by action-date commitment order: effective action date, then importance, then identity. */
export function compareTaskByActionDateThenPriority(a: Task, b: Task): number {
  const actionDateCompare = compareNullableTextNullsLast(taskEffectiveActionDate(a), taskEffectiveActionDate(b));
  if (actionDateCompare !== 0) return actionDateCompare;
  const dueDateCompare = compareNullableTextNullsLast(a.due_date, b.due_date);
  if (dueDateCompare !== 0) return dueDateCompare;
  const dueTimeCompare = compareNullableTextNullsLast(a.due_time, b.due_time);
  if (dueTimeCompare !== 0) return dueTimeCompare;
  const priorityCompare = compareTaskPriority(a, b);
  if (priorityCompare !== 0) return priorityCompare;
  return compareTaskId(a, b);
}

/** Sort by planned-date order first, then concrete deadline risk, then importance, then identity. */
export function compareTaskByPlannedDateThenPriority(a: Task, b: Task): number {
  const plannedDateCompare = compareNullableTextNullsLast(a.planned_date, b.planned_date);
  if (plannedDateCompare !== 0) return plannedDateCompare;
  const dueDateCompare = compareNullableTextNullsLast(a.due_date, b.due_date);
  if (dueDateCompare !== 0) return dueDateCompare;
  const dueTimeCompare = compareNullableTextNullsLast(a.due_time, b.due_time);
  if (dueTimeCompare !== 0) return dueTimeCompare;
  const priorityCompare = compareTaskPriority(a, b);
  if (priorityCompare !== 0) return priorityCompare;
  return compareTaskId(a, b);
}
