import { useCallback, useEffect, useRef, type RefObject } from 'react';

import { useCopyToClipboard } from '@/lib/platform/useCopyToClipboard';
import { parseTags } from '@/lib/format';
import { shouldIgnoreShortcut } from '@/lib/shortcutGuard';
import { isEditableTarget as isEditableTargetCheck } from '@/lib/editableTarget';
import type { TaskDetailControllerState } from '../support';
import { TaskDetailErrorState, TaskDetailLoadingState } from './TaskDetailStateViews';
import {
  TaskDetailBodySections,
  TaskDetailHeader,
  TaskDetailTitleEditor,
} from './detail-content';
import {
  useHashtagAutocomplete,
} from '@/components/tag-autocomplete/useHashtagAutocomplete';
import {
  installTaskDetailShortcutRuntime,
} from './TaskDetailContent.runtime';
import { TASK_STATUS } from '@lorvex/shared/types';

interface TaskDetailContentProps {
  controller: TaskDetailControllerState;
  /**
   * Forwarded to the title input so the enclosing SlidePanel can move
   * focus to it on open. Optional.
   */
  titleRef?: RefObject<HTMLInputElement | null> | undefined;
}

export default function TaskDetailContent({ controller, titleRef }: TaskDetailContentProps) {
  const {
    bodyDraft,
    contentClass,
    error,
    handleBodyDraftChange,
    handleBodyDirtyChange,
    handleClose,
    handleTitleBlur,
    handleTitleChange,
    handleTitleCompositionEnd,
    handleTitleCompositionStart,
    handleTitleKeyDown,
    headerClass,
    headerStyle,
    isCompleting,
    isComplete,
    isLoading,
    locale,
    overdue,
    persistBody,
    refetchTask,
    saveMetaPatch,
    shellClass,
    statusLabel,
    t,
    task,
    taskId,
    titleComposing,
    titleDraft,
  } = controller;

  const controllerRef = useRef(controller);
  controllerRef.current = controller;

  useEffect(() => {
    return installTaskDetailShortcutRuntime({
      windowTarget: window,
      getController: () => {
        const ctrl = controllerRef.current;
        return {
          isComplete: ctrl.isComplete,
          taskStatus: ctrl.task?.status,
          handleClose: ctrl.handleClose,
          handleComplete: ctrl.handleComplete,
          handleDefer: ctrl.handleDefer,
          handleReopen: ctrl.handleReopen,
        };
      },
      shouldIgnoreShortcutTarget: shouldIgnoreShortcut,
      isEditableTarget: isEditableTargetCheck,
    });
  }, []);

  const { copy } = useCopyToClipboard();
  const copyTaskId = useCallback(() => {
    void copy(taskId);
  }, [copy, taskId]);

  // `#`-prefixed tag autocomplete in the title editor.
  // We route the accepted tag through `saveMetaPatch({ tags: [...] })`
  // instead of the comma-separated draft used in quick-capture
  // because the detail panel persists field-by-field (there's no
  // "submit" to batch the write into).
  //
  // Fall back to an internal ref when the enclosing panel doesn't
  // pass one — keeps the hook's caret-tracking working whether or
  // not the SlidePanel focus handoff is wired up.
  const internalTitleRef = useRef<HTMLInputElement | null>(null);
  const resolvedTitleRef = (titleRef ?? internalTitleRef) as RefObject<HTMLInputElement | null>;
  const currentTags = task ? parseTags(task.tags) : [];
  const hashtag = useHashtagAutocomplete({
    inputRef: resolvedTitleRef,
    value: titleDraft,
    disabled: titleComposing || !task,
    currentTags,
    onAcceptTag: (tagName, nextTitle) => {
      handleTitleChange(nextTitle);
      // Persist tags immediately — the title draft will commit on
      // its normal blur path. We skip the write if the tag is
      // already present (defensive; `currentTags` also filters).
      if (currentTags.some((existing) => existing.toLowerCase() === tagName.toLowerCase())) return;
      const nextTags = [...currentTags, tagName];
      void saveMetaPatch({ tags: nextTags });
    },
  });

  if (isLoading) {
    return (
      <TaskDetailLoadingState
        isMobile={controller.isMobile}
        onClose={() => { void handleClose(); }}
        t={t}
      />
    );
  }

  if (error || !task) {
    return (
      <TaskDetailErrorState
        isMobile={controller.isMobile}
        onClose={() => { void handleClose(); }}
        hasError={error !== null && error !== undefined}
        onRetry={() => { void refetchTask(); }}
        t={t}
      />
    );
  }

  const actionBarController = { ...controller, task };
  const isActionable = task.status === TASK_STATUS.open || task.status === TASK_STATUS.someday;

  return (
    <div className={shellClass}>
      <TaskDetailHeader
        controller={controller}
        copyTaskId={copyTaskId}
        headerClass={headerClass}
        headerStyle={headerStyle}
        isActionable={isActionable}
        isComplete={isComplete}
        isCompleting={isCompleting}
        statusLabel={statusLabel}
        task={task}
        taskId={taskId}
        t={t}
      />

      <div className={contentClass}>
        <TaskDetailTitleEditor
          handleTitleBlur={handleTitleBlur}
          handleTitleChange={handleTitleChange}
          handleTitleCompositionEnd={handleTitleCompositionEnd}
          handleTitleCompositionStart={handleTitleCompositionStart}
          handleTitleKeyDown={handleTitleKeyDown}
          hashtag={hashtag}
          isComplete={isComplete}
          resolvedTitleRef={resolvedTitleRef}
          t={t}
          titleDraft={titleDraft}
        />

        <TaskDetailBodySections
          actionBarController={actionBarController}
          bodyDraft={bodyDraft}
          controller={controller}
          handleBodyDirtyChange={handleBodyDirtyChange}
          handleBodyDraftChange={handleBodyDraftChange}
          isActionable={isActionable}
          locale={locale}
          overdue={overdue}
          persistBody={persistBody}
          refetchTask={refetchTask}
          saveMetaPatch={saveMetaPatch}
          task={task}
          taskId={taskId}
          t={t}
        />
      </div>
    </div>
  );
}
