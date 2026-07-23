import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useMounted } from '@/lib/useMounted';
import { useQuery, useQueryClient } from '@tanstack/react-query';

import { useDayContext } from '@/lib/DayContextProvider';
import { STALE_DEFAULT } from '@/lib/query/timing';
import { reportClientError } from '@/lib/errors/errorLogging';
import { useI18n } from '@/lib/i18n';
import { getAllLists } from '@/lib/ipc/tasks/lists';
import type { Task } from '@/lib/ipc/tasks/models';
import { completeTask, reopenTask } from '@/lib/ipc/tasks/mutations/lifecycle';
import { updateTask } from '@/lib/ipc/tasks/mutations/quickCapture';
import { formatDueDate, isDueOverdue, isDueToday, parseTags } from '@/lib/format';
import { QUERY_KEYS, invalidateTaskMutationQueries, invalidateTaskQueries } from '@/lib/query/queryKeys';
import { showUndoToastWithRedo } from '@/lib/tasks/lifecycleUndoRedo';
import { toast } from '@/lib/notifications/toast';

import {
  TASK_COMPLETE_ANIMATION_DELAY_MS,
  type TaskCardActionHandler,
  type TaskCardDisplayLabels,
  parseChecklistProgress,
} from './support';
import { projectTaskBodyContent } from '@/lib/tasks/contentProjection';
import {
  clearTaskCardCompletionRefresh,
  createBrowserTaskCardCompletionRefreshTimerHost,
  createTaskCardCompletionRefreshAbortToken,
  scheduleTaskCardCompletionRefresh,
  type TaskCardCompletionRefreshAbortToken,
} from './taskCardCompletionRefresh.runtime';
import { TASK_STATUS } from '@lorvex/shared/types';

interface UseTaskCardControllerOptions {
  task: Task;
  completed: boolean;
  disableComplete: boolean;
}

export function useTaskCardController({
  task,
  completed,
  disableComplete,
}: UseTaskCardControllerOptions) {
  const qc = useQueryClient();
  const { t, locale } = useI18n();
  const dayContext = useDayContext();
  const [completing, setCompleting] = useState(false);
  const [reopening, setReopening] = useState(false);
  const [locallyCompleted, setLocallyCompleted] = useState(false);
  const taskCardMountedRef = useMounted();
  const isDone = completed || task.status === TASK_STATUS.completed || task.status === TASK_STATUS.cancelled || locallyCompleted;
  const canQuickReopen = isDone && !disableComplete;

  // Read list name/color from the already-cached ['lists'] query (no extra fetch)
  const { data: lists = [] } = useQuery({
    queryKey: QUERY_KEYS.lists(),
    queryFn: ({ signal }) => getAllLists(signal),
    staleTime: STALE_DEFAULT,
  });
  const listInfo = useMemo(() => {
    const list = lists.find((l) => l.id === task.list_id);
    return list ? { name: list.name, color: list.color } : null;
  }, [task.list_id, lists]);

  const bodyProjection = useMemo(() => projectTaskBodyContent(task.body), [task.body]);
  const checklistProgress = useMemo(() => parseChecklistProgress(task), [task]);
  const bodySnippet = bodyProjection.bodySnippet;
  const tags = parseTags(task.tags);
  const dueDateStr = formatDueDate(task.due_date, {
    dayContext,
    locale,
    todayLabel: t('upcoming.today'),
    tomorrowLabel: t('upcoming.tomorrow'),
    yesterdayLabel: t('upcoming.yesterday'),
  });
  const overdue = isDueOverdue(task.due_date, dayContext) && !isDone;
  const dueToday = isDueToday(task.due_date, dayContext) && !isDone;
  const labels: TaskCardDisplayLabels = useMemo(() => ({
    complete: t('task.complete'),
    reopen: t('task.reopen'),
    completed: t('task.status.completed'),
    recurrence: t('task.recurrence'),
    minuteSuffix: t('common.min'),
    dependsOn: t('task.dependsOn'),
    overdue: t('today.overdue'),
    dueToday: t('today.dueToday'),
    aiNotes: t('task.aiNotes'),
    priorityLabels: { 1: t('task.priorityP1'), 2: t('task.priorityP2'), 3: t('task.priorityP3') },
  }), [t]);

  const invalidateTaskCaches = useCallback(() => {
    invalidateTaskMutationQueries(qc, { listId: task.list_id });
    invalidateTaskQueries(qc, task.id);
  }, [qc, task.id, task.list_id]);

  const reportTaskCardError = useCallback((action: string, error: unknown, severity: 'warn' | 'error' = 'error') => {
    reportClientError(
      `taskCard.${action}`,
      `Task card action failed: ${action}`,
      error,
      task.id,
      severity,
    );
  }, [task.id]);

  // Track the in-flight completion-refresh timer so the undo toast
  // can cancel it BEFORE invoking its own cache invalidate.
  // Otherwise the undo handler invalidates, then ~250ms later the
  // already-scheduled refresh fires a second invalidate against the
  // now-restored task — with the optimistic `locallyCompleted` bit
  // cleared in between, the task briefly flickers back to the
  // "completed" appearance.
  const pendingCompletionRefreshRef = useRef<{
    handle: unknown;
    token: TaskCardCompletionRefreshAbortToken;
  } | null>(null);

  const cancelPendingCompletionRefresh = useCallback(() => {
    const pending = pendingCompletionRefreshRef.current;
    if (!pending) return;
    pending.token.abort();
    clearTaskCardCompletionRefresh(
      createBrowserTaskCardCompletionRefreshTimerHost(),
      pending.handle,
    );
    pendingCompletionRefreshRef.current = null;
  }, []);

  // Cancel any orphaned timer if the card unmounts mid-window.
  useEffect(() => () => cancelPendingCompletionRefresh(), [cancelPendingCompletionRefresh]);

  const handleCompleteAsync = async (event: Parameters<TaskCardActionHandler>[0]) => {
    event.stopPropagation();
    if (disableComplete || isDone || completing) return;

    // A new complete supersedes any prior in-flight refresh — drop the
    // stale handle so its callback can't race the new write.
    cancelPendingCompletionRefresh();

    setCompleting(true);
    setLocallyCompleted(true);

    try {
      const result = await completeTask(task.id);
      showUndoToastWithRedo(`${labels.completed}: ${task.title}`, result.undo_token, {
        invalidate: () => {
          // abort the pending refresh BEFORE running our
          // own invalidate. The abort is best-effort — if the timer
          // already fired and is mid-execution, the abortToken check
          // inside scheduleTaskCardCompletionRefresh's wrapper still
          // suppresses the stale invalidate.
          cancelPendingCompletionRefresh();
          if (taskCardMountedRef.current) {
            setLocallyCompleted(false);
          }
          invalidateTaskCaches();
        },
        t,
        errorKeyPrefix: 'taskCard.complete',
      });
      // Let the "completed" visual state be perceivable before list refresh hides it.
      const token = createTaskCardCompletionRefreshAbortToken();
      const handle = scheduleTaskCardCompletionRefresh({
        delayMs: TASK_COMPLETE_ANIMATION_DELAY_MS,
        refresh: () => {
          // Clear our own slot when we fire normally so the next
          // complete starts from a clean state.
          if (pendingCompletionRefreshRef.current?.handle === handle) {
            pendingCompletionRefreshRef.current = null;
          }
          invalidateTaskCaches();
        },
        timerHost: createBrowserTaskCardCompletionRefreshTimerHost(),
        abortToken: token,
      });
      pendingCompletionRefreshRef.current = { handle, token };
    } catch (error) {
      if (taskCardMountedRef.current) {
        setLocallyCompleted(false);
      }
      reportTaskCardError('complete', error);
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      if (taskCardMountedRef.current) {
        setCompleting(false);
      }
    }
  };

  const handleComplete: TaskCardActionHandler = (event) => { void handleCompleteAsync(event); };

  const handleReopenAsync = async (event: Parameters<TaskCardActionHandler>[0]) => {
    event.stopPropagation();
    if (!canQuickReopen || reopening || completing) return;

    setReopening(true);

    try {
      await reopenTask(task.id);
      if (taskCardMountedRef.current) {
        setLocallyCompleted(false);
      }
      invalidateTaskCaches();
      toast.info(t('task.undone'));
    } catch (error) {
      reportTaskCardError('reopen', error);
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      if (taskCardMountedRef.current) {
        setReopening(false);
      }
    }
  };

  const handleReopen: TaskCardActionHandler = (event) => { void handleReopenAsync(event); };

  const [isEditingTitle, setIsEditingTitle] = useState(false);
  // A rename triggered by blur fires `updateTask` but returns
  // control to the user before the IPC resolves. Track the in-flight
  // save so the input stays mounted in a disabled "saving" state
  // until the IPC settles — otherwise a subsequent click on a
  // sibling row B fires both the blur on row A and a click-through
  // that opens B's detail panel, and the row A title can flicker to
  // a stale value if the server still has it cached.
  const [isSavingTitle, setIsSavingTitle] = useState(false);

  const handleTitleSave = useCallback(async (newTitle: string) => {
    const trimmed = newTitle.trim();
    if (!trimmed || trimmed === task.title) {
      setIsEditingTitle(false);
      return;
    }
    setIsSavingTitle(true);
    try {
      await updateTask(task.id, { title: trimmed });
      invalidateTaskCaches();
    } catch (error) {
      reportTaskCardError('inlineRename', error, 'warn');
      toast.errorWithDetail(error, t('common.error'));
    } finally {
      if (taskCardMountedRef.current) {
        setIsEditingTitle(false);
        setIsSavingTitle(false);
      }
    }
  }, [task.id, task.title, t, taskCardMountedRef, invalidateTaskCaches, reportTaskCardError]);

  return {
    bodySnippet,
    canQuickReopen,
    checklistProgress,
    completing,
    dueDateStr,
    dueToday,
    handleComplete,
    handleReopen,
    handleTitleSave,
    isDone,
    isEditingTitle,
    isSavingTitle,
    labels,
    listInfo,
    overdue,
    reopening,
    setIsEditingTitle,
    tags,
  };
}
