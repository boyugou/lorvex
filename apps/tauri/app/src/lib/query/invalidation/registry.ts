import { QK } from '../queryKeyHeads';
import { queryHeadList } from './batch';
import {
  CALENDAR_MUTATION_QUERY_KEY_HEADS,
  CALENDAR_SUBSCRIPTION_QUERY_KEY_HEADS,
  CALENDAR_VIEW_QUERY_KEY_HEADS,
  DAILY_REVIEW_WRITE_QUERY_KEY_HEADS,
  DATA_IMPORT_QUERY_KEY_HEADS,
  FOCUS_SCHEDULE_QUERY_KEY_HEADS,
  FOCUS_TASK_QUERY_KEY_HEADS,
  HABIT_WRITE_QUERY_KEY_HEADS,
  PLANNING_FOCUS_QUERY_KEY_HEADS,
  TASK_COLLECTION_QUERY_KEY_HEADS,
  TASK_DEPENDENCY_QUERY_KEY_HEADS,
  TASK_DEPENDENCY_WRITE_QUERY_KEY_HEADS,
  TASK_DETAIL_QUERY_KEY_HEADS,
  TASK_DETAIL_WRITE_EXTRA_QUERY_KEY_HEADS,
  TASK_INDEX_QUERY_KEY_HEADS,
  TASK_MUTATION_QUERY_KEY_HEADS,
  TASK_STATUS_CHANGE_QUERY_KEY_HEADS,
  TODAY_SURFACE_QUERY_KEY_HEADS,
  TODAY_TASK_INDEX_QUERY_KEY_HEADS,
} from './groups';

export const QUERY_INVALIDATION_REGISTRY = {
  'today.surface': queryHeadList(...TODAY_SURFACE_QUERY_KEY_HEADS),
  'today.bootstrap': queryHeadList(QK.todayBootstrap),
  'today.taskIndex': queryHeadList(...TODAY_TASK_INDEX_QUERY_KEY_HEADS),
  'task.index': queryHeadList(...TASK_INDEX_QUERY_KEY_HEADS),
  'task.collection': queryHeadList(...TASK_COLLECTION_QUERY_KEY_HEADS),
  'task.detail': queryHeadList(...TASK_DETAIL_QUERY_KEY_HEADS),
  'task.write': queryHeadList(...TODAY_SURFACE_QUERY_KEY_HEADS, ...TASK_MUTATION_QUERY_KEY_HEADS),
  'task.workspace': queryHeadList(
    ...TODAY_SURFACE_QUERY_KEY_HEADS,
    ...TASK_COLLECTION_QUERY_KEY_HEADS,
    ...TASK_DETAIL_QUERY_KEY_HEADS,
  ),
  'task.statusChange': queryHeadList(...TASK_STATUS_CHANGE_QUERY_KEY_HEADS),
  'task.dependency': queryHeadList(...TASK_DEPENDENCY_QUERY_KEY_HEADS),
  'task.dependencyWrite': queryHeadList(...TASK_DEPENDENCY_WRITE_QUERY_KEY_HEADS),
  'task.detailWrite.extra': queryHeadList(...TASK_DETAIL_WRITE_EXTRA_QUERY_KEY_HEADS),
  'list.contextTaskWrite': queryHeadList(...TODAY_SURFACE_QUERY_KEY_HEADS, QK.lists, QK.allTasks),
  'data.import': queryHeadList(...DATA_IMPORT_QUERY_KEY_HEADS),
  'calendar.eventWrite': queryHeadList(...CALENDAR_MUTATION_QUERY_KEY_HEADS),
  'calendar.subscriptionWrite': queryHeadList(...CALENDAR_SUBSCRIPTION_QUERY_KEY_HEADS),
  'calendar.view': queryHeadList(...CALENDAR_VIEW_QUERY_KEY_HEADS),
  'focus.schedule': queryHeadList(...FOCUS_SCHEDULE_QUERY_KEY_HEADS),
  'focus.planning': queryHeadList(...PLANNING_FOCUS_QUERY_KEY_HEADS),
  'focus.taskWrite': queryHeadList(...FOCUS_TASK_QUERY_KEY_HEADS),
  'habit.write': queryHeadList(...HABIT_WRITE_QUERY_KEY_HEADS),
  'dailyReview.write': queryHeadList(...DAILY_REVIEW_WRITE_QUERY_KEY_HEADS),
} as const;

export type QueryInvalidationIntent = keyof typeof QUERY_INVALIDATION_REGISTRY;

export function queryKeyHeadsForInvalidationIntent(
  intent: QueryInvalidationIntent,
) {
  return QUERY_INVALIDATION_REGISTRY[intent];
}
