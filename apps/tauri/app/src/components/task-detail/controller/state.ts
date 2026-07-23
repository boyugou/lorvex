import { useMemo } from 'react';

import type { DayContext } from '@/lib/dayContext';
import { isDueOverdue } from '@/lib/format';
import type { TranslationKey } from '@/lib/i18n';
import type { TaskDetailControllerState } from '../support';
import type { TaskDetailDraftState } from './drafts';
import type { TaskDetailMutationState } from './mutations';
import { TASK_STATUS } from '@lorvex/shared/types';

const STATUS_LABEL_KEYS = {
  open: 'task.status.open',
  completed: 'task.status.completed',
  cancelled: 'task.status.cancelled',
  someday: 'task.status.someday',
} as const;

interface UseTaskDetailControllerStateArgs {
  attribution: TaskDetailControllerState['attribution'];
  blocksIds: string[];
  dayContext: DayContext;
  dependsOnIds: string[];
  depTaskMap: TaskDetailControllerState['depTaskMap'];
  drafts: TaskDetailDraftState;
  error: unknown;
  handleClose: () => Promise<void>;
  handleDefer: (untilDate: string | null) => Promise<void>;
  isLoading: boolean;
  isMobile: boolean;
  locale: string;
  mutations: TaskDetailMutationState;
  onSelectTask?: ((id: string) => void) | undefined;
  refetchTask: () => Promise<unknown>;
  t: (key: TranslationKey) => string;
  task: TaskDetailControllerState['task'];
  taskId: string;
}

export function useTaskDetailControllerState({
  attribution,
  blocksIds,
  dayContext,
  dependsOnIds,
  depTaskMap,
  drafts,
  error,
  handleClose,
  handleDefer,
  isLoading,
  isMobile,
  locale,
  mutations,
  onSelectTask,
  refetchTask,
  t,
  task,
  taskId,
}: UseTaskDetailControllerStateArgs): TaskDetailControllerState {
  const statusLabel = t(STATUS_LABEL_KEYS[task?.status as keyof typeof STATUS_LABEL_KEYS] ?? 'task.status.open');
  const overdue = task !== null && isDueOverdue(task.due_date, dayContext) && task.status !== TASK_STATUS.completed && task.status !== TASK_STATUS.cancelled;
  const isComplete = task?.status === TASK_STATUS.completed;
  const shellClass = `h-full flex flex-col bg-surface-1 overflow-hidden clarity-first-surface ${isMobile ? '' : 'border-s border-surface-3'}`;
  const headerClass = isMobile
    ? 'flex items-center justify-between px-4 pb-3 shrink-0'
    : 'flex items-center justify-between px-6 pt-4 pb-3 shrink-0';
  const headerStyle = useMemo(
    () => isMobile
      ? { paddingTop: 'max(1rem, env(safe-area-inset-top, 1rem))' }
      : undefined,
    [isMobile],
  );
  const contentClass = isMobile
    ? 'flex-1 min-h-0 overflow-y-auto overscroll-contain px-4 pb-20 pt-4 space-y-4'
    : 'flex-1 min-h-0 overflow-y-auto overscroll-contain px-6 pb-8 pt-5 space-y-4';

  return useMemo<TaskDetailControllerState>(() => ({
    actionPending: mutations.actionPending,
    attribution,
    blocksIds,
    bodyDraft: drafts.bodyDraft,
    contentClass,
    dependsOnIds,
    depTaskMap,
    error,
    handleBodyDraftChange: drafts.handleBodyDraftChange,
    handleBodyDirtyChange: drafts.handleBodyDirtyChange,
    handleClose,
    handleComplete: mutations.handleComplete,
    handleDelete: mutations.handleDelete,
    handleDuplicate: mutations.handleDuplicate,
    handlePermanentDelete: mutations.handlePermanentDelete,
    handleReopen: mutations.handleReopen,
    handleResetDeferral: mutations.handleResetDeferral,
    handleDefer,
    handleTitleBlur: drafts.handleTitleBlur,
    handleTitleChange: drafts.handleTitleChange,
    handleTitleCompositionEnd: drafts.handleTitleCompositionEnd,
    handleTitleCompositionStart: drafts.handleTitleCompositionStart,
    handleTitleKeyDown: drafts.handleTitleKeyDown,
    headerClass,
    headerStyle,
    isCompleting: mutations.isCompleting,
    isComplete,
    isLoading,
    isMobile,
    locale,
    onSelectTask,
    overdue,
    persistBody: drafts.persistBody,
    refetchTask,
    savingBody: drafts.savingBody,
    savingTitle: drafts.savingTitle,
    saveMetaPatch: mutations.saveMetaPatch,
    shellClass,
    statusLabel,
    t,
    task,
    taskId,
    titleComposing: drafts.titleComposing,
    titleDraft: drafts.titleDraft,
    titleDirty: drafts.titleDirty,
    unsavedChanges: drafts.titleDirty || drafts.bodyDirty || drafts.savingTitle || drafts.savingBody,
  }), [
    attribution,
    blocksIds,
    contentClass,
    dependsOnIds,
    depTaskMap,
    drafts.bodyDraft,
    drafts.bodyDirty,
    drafts.handleBodyDraftChange,
    drafts.handleBodyDirtyChange,
    drafts.handleTitleBlur,
    drafts.handleTitleChange,
    drafts.handleTitleCompositionEnd,
    drafts.handleTitleCompositionStart,
    drafts.handleTitleKeyDown,
    drafts.persistBody,
    drafts.savingBody,
    drafts.savingTitle,
    drafts.titleComposing,
    drafts.titleDirty,
    drafts.titleDraft,
    error,
    handleClose,
    handleDefer,
    headerClass,
    headerStyle,
    isComplete,
    isLoading,
    isMobile,
    locale,
    mutations.actionPending,
    mutations.handleComplete,
    mutations.handleDelete,
    mutations.handleDuplicate,
    mutations.handlePermanentDelete,
    mutations.handleReopen,
    mutations.handleResetDeferral,
    mutations.isCompleting,
    mutations.saveMetaPatch,
    onSelectTask,
    overdue,
    refetchTask,
    shellClass,
    statusLabel,
    t,
    task,
    taskId,
  ]);
}
