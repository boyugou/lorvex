import { memo, useMemo, useEffect, useRef, useState } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import { useI18n } from '@/lib/i18n';
import { isImeComposing } from '@/lib/ime';
import { CalendarUpcomingIcon, CheckIcon, WarningIcon } from '../ui/icons';
import { Tooltip } from '../ui/Tooltip';

import { PRIORITY_ICONS, type ChecklistProgress, type TaskCardDisplayLabels, type TaskCardProps } from './support';

interface TaskCardContentProps {
  task: Task;
  isDone: boolean;
  completing: boolean;
  dueDateStr: string | null;
  overdue: boolean;
  dueToday?: boolean;
  bodySnippet?: string | null;
  tags: string[];
  checklistProgress: ChecklistProgress | null;
  labels: TaskCardDisplayLabels;
  listInfo?: { name: string; color: string | null } | null;
  onClick?: TaskCardProps['onClick'];
  onKeyDown?: TaskCardProps['onKeyDown'];
  taskButtonRole?: TaskCardProps['taskButtonRole'];
  taskButtonAriaChecked?: TaskCardProps['taskButtonAriaChecked'];
  taskButtonAriaLabel?: TaskCardProps['taskButtonAriaLabel'];
  taskButtonAriaDescription?: TaskCardProps['taskButtonAriaDescription'];
  taskButtonAriaRoleDescription?: TaskCardProps['taskButtonAriaRoleDescription'];
  taskButtonAriaKeyShortcuts?: TaskCardProps['taskButtonAriaKeyShortcuts'];
  taskButtonDisabled?: TaskCardProps['taskButtonDisabled'];
  isEditingTitle?: boolean;
  /**
   * when true, the rename IPC is in flight. The input
   * stays mounted but disabled, and a "saving" affordance is shown so
   * the user knows their value is being committed (and so a stray
   * click on a sibling row doesn't fire a click-through with stale
   * state).
   */
  isSavingTitle?: boolean;
  onStartEditTitle?: () => void;
  onTitleSave?: (title: string) => void;
  onTitleCancel?: () => void;
}

export const TaskCardContent = memo(function TaskCardContent({
  task,
  isDone,
  completing,
  dueDateStr,
  overdue,
  dueToday = false,
  bodySnippet,
  tags,
  checklistProgress,
  labels,
  listInfo,
  onClick,
  onKeyDown,
  taskButtonRole,
  taskButtonAriaChecked,
  taskButtonAriaLabel,
  taskButtonAriaDescription,
  taskButtonAriaRoleDescription,
  taskButtonAriaKeyShortcuts,
  taskButtonDisabled = false,
  isEditingTitle = false,
  isSavingTitle = false,
  onStartEditTitle,
  onTitleSave,
  onTitleCancel,
}: TaskCardContentProps) {
  const { t } = useI18n();
  const isClickable = !!onClick;
  const inputRef = useRef<HTMLInputElement>(null);
  const [editValue, setEditValue] = useState(task.title);
  // Track whether we already submitted from this edit session so a
  // blur-after-Enter doesn't double-fire the save IPC.
  const submittedRef = useRef(false);

  // Focus the input when entering edit mode
  useEffect(() => {
    if (isEditingTitle && !isSavingTitle && inputRef.current) {
      setEditValue(task.title);
      submittedRef.current = false;
      inputRef.current.focus();
      inputRef.current.select();
    }
  }, [isEditingTitle, isSavingTitle, task.title]);

  const handleClick = (event: React.MouseEvent<HTMLButtonElement>) => {
    if (isEditingTitle) return;
    onClick?.(event);
  };

  const handleDoubleClick = (event: React.MouseEvent) => {
    event.stopPropagation();
    event.preventDefault();
    if (onStartEditTitle && !isDone) {
      onStartEditTitle();
    }
  };

  const handleEditKeyDown = (event: React.KeyboardEvent<HTMLInputElement>) => {
    event.stopPropagation();
    if (event.key === 'Enter' && !isImeComposing(event)) {
      event.preventDefault();
      submittedRef.current = true;
      onTitleSave?.(editValue);
    } else if (event.key === 'Escape') {
      event.preventDefault();
      submittedRef.current = true;
      onTitleCancel?.();
    }
  };

  const handleEditBlur = () => {
    if (submittedRef.current) return;
    submittedRef.current = true;
    onTitleSave?.(editValue);
  };

  // cancel a click-through onto a sibling row B that
  // would have fired both the editing input's blur (commits row A)
  // and a click on row B (opens detail). We pre-empt the click in the
  // pointerdown phase: if a pointerdown happens outside the input
  // while we're still editing, we eagerly commit so the subsequent
  // click event sees the input already unmounted (or in saving state)
  // and doesn't get re-routed through it. The pointerdown listener is
  // attached to the document only while editing.
  useEffect(() => {
    if (!isEditingTitle || isSavingTitle) return;
    const onPointerDown = (event: PointerEvent) => {
      const input = inputRef.current;
      if (!input) return;
      const target = event.target;
      if (target instanceof Node && input.contains(target)) return;
      if (submittedRef.current) return;
      submittedRef.current = true;
      onTitleSave?.(input.value);
    };
    document.addEventListener('pointerdown', onPointerDown, true);
    return () => document.removeEventListener('pointerdown', onPointerDown, true);
  }, [isEditingTitle, isSavingTitle, onTitleSave]);

  const descriptionId = `task-desc-${task.id}`;
  const accessibleDescription = useMemo(() => {
    const parts: string[] = [];
    if (isDone) parts.push(labels.completed);
    if (dueDateStr) {
      // surface the due-today / overdue qualifier in
      // the SR description too, so scanning the card list reveals the
      // state without focusing into the inline badge.
      const qualifier = overdue
        ? ` (${labels.overdue})`
        : dueToday
          ? ` (${labels.dueToday})`
          : '';
      parts.push(`${dueDateStr}${qualifier}`);
    }
    if (task.due_time) parts.push(task.due_time);
    if (task.estimated_minutes != null && task.estimated_minutes > 0) {
      parts.push(`${task.estimated_minutes}${labels.minuteSuffix}`);
    }
    if (checklistProgress) parts.push(`${checklistProgress.done}/${checklistProgress.total}`);
    if (tags.length > 0) parts.push(tags.join(', '));
    if (listInfo) parts.push(listInfo.name);
    return parts.join(', ');
  }, [isDone, dueDateStr, overdue, dueToday, task.due_time, task.estimated_minutes, checklistProgress, tags, listInfo, labels]);

  const contentClass = `flex-1 min-w-0 ${isClickable && !isEditingTitle ? 'text-start rounded-r-control focus-ring-soft' : ''}`;

  const titleElement = isEditingTitle ? (
    <span className="flex items-center gap-2 flex-1 min-w-0">
      <input
        ref={inputRef}
        value={editValue}
        disabled={isSavingTitle}
        aria-busy={isSavingTitle || undefined}
        onChange={(event) => setEditValue(event.target.value)}
        onKeyDown={handleEditKeyDown}
        onBlur={handleEditBlur}
        onClick={(event) => event.stopPropagation()}
        // the inline rename input previously
        // shipped without a programmatic label. Screen readers
        // announced it as a bare edit field — the surrounding card's
        // `aria-label` (the task title) sits on the wrapping
        // `<button>`, not on the input, so once focus moved into the
        // field there was no labelling relationship for AT to follow.
        // Tag it with the canonical "Task title" string so SR users
        // hear the field's purpose when they tab in or double-click
        // to edit.
        aria-label={t('task.title')}
        className={`text-sm leading-snug flex-1 min-w-0 text-text-primary bg-transparent border-b border-accent/40 outline-hidden focus-ring-soft w-full ${
          isSavingTitle ? 'opacity-60 cursor-progress' : ''
        }`}
      />
      {isSavingTitle && (
        <span
          role="status"
          aria-live="polite"
          className="shrink-0 text-3xs text-text-muted tabular-nums uppercase tracking-wide"
        >
          {t('common.saving')}
        </span>
      )}
    </span>
  ) : (
    <Tooltip label={task.title}>
      {/* Double-click-to-rename is mouse-specific; F2 (or the row
          context menu's Rename action) is the keyboard alternative
          and is wired on the surrounding card controller. */}
      {/* eslint-disable-next-line jsx-a11y/no-static-element-interactions */}
      <span
        className={`text-sm truncate flex-1 transition-opacity duration-200 ${
          isDone
            ? 'text-text-secondary line-through'
            : completing
              ? 'text-text-muted opacity-50 task-strike-sweep'
              : 'text-text-primary'
        }`}
        onDoubleClick={handleDoubleClick}
      >
        {task.title}
      </span>
    </Tooltip>
  );

  const body = (
    <>
      {/* Title */}
      {titleElement}

      {/* Compact metadata line — always rendered for consistent 2-line height */}
      <div className={`flex items-center gap-1.5 mt-1 min-h-[1.25rem] text-xs transition-opacity duration-200 ${completing ? 'opacity-30' : ''}`}>
        {isDone && (
          <span className="font-medium text-success inline-flex items-center gap-0.5">
            <CheckIcon className="w-3 h-3" /> {labels.completed}
          </span>
        )}
        {task.priority != null && task.priority <= 2 && (
          <span className="text-danger shrink-0" role="img" aria-label={labels.priorityLabels[task.priority]}>
            {PRIORITY_ICONS[task.priority]}
          </span>
        )}
        {(dueDateStr || task.due_time) && (
          <Tooltip label={task.due_date ?? ''} disabled={!task.due_date}>
            <span
              className={`tabular-nums shrink-0 inline-flex items-center gap-0.5 ${overdue ? 'text-danger font-medium' : dueToday ? 'text-accent' : 'text-text-muted/70'}`}
            >
              {overdue ? (
                // pair the red color with an icon + sr-only
                // label so overdue status is recoverable on grayscale /
                // high-contrast themes and by screen readers (WCAG 1.4.1).
                <>
                  <WarningIcon className="w-3 h-3 shrink-0" aria-hidden="true" />
                  <span className="sr-only">{labels.overdue}: </span>
                </>
              ) : dueToday ? (
                // dueToday was the only remaining
                // date-state cue that relied solely on accent color.
                // Mirror the overdue treatment so SR/grayscale users
                // still recover the meaning, but with a calendar icon
                // (not a warning) so sighted users don't conflate "due
                // today" with "overdue".
                <>
                  <CalendarUpcomingIcon className="w-3 h-3 shrink-0" aria-hidden="true" />
                  <span className="sr-only">{labels.dueToday}: </span>
                </>
              ) : null}
              {dueDateStr}{task.due_time ? ` ${task.due_time}` : ''}
            </span>
          </Tooltip>
        )}
        {task.recurrence && (
          <Tooltip label={labels.recurrence}>
            <span className="text-text-muted shrink-0" role="img" aria-label={labels.recurrence}>↻</span>
          </Tooltip>
        )}
        {listInfo && (
          <span className="flex items-center gap-1 text-text-muted/50 shrink-0 max-w-[8rem]">
            <span className="w-1.5 h-1.5 rounded-full shrink-0" style={{ backgroundColor: listInfo.color || 'var(--color-text-muted)' }} />
            <span className="truncate">{listInfo.name}</span>
          </span>
        )}
        {bodySnippet && !isDone && (
          <span className="text-text-muted/60 truncate italic">{bodySnippet}</span>
        )}
      </div>
    </>
  );

  if (isClickable && !isEditingTitle) {
    return (
      <button
        type="button"
        role={taskButtonRole}
        onClick={handleClick}
        onKeyDown={onKeyDown}
        disabled={taskButtonDisabled}
        className={contentClass}
        aria-label={taskButtonAriaLabel ?? task.title}
        aria-checked={taskButtonAriaChecked}
        aria-description={taskButtonAriaDescription}
        aria-roledescription={taskButtonAriaRoleDescription}
        aria-keyshortcuts={taskButtonAriaKeyShortcuts}
        aria-describedby={accessibleDescription ? descriptionId : undefined}
      >
        {body}
        {accessibleDescription && (
          <span id={descriptionId} className="sr-only">{accessibleDescription}</span>
        )}
      </button>
    );
  }

  return <div className="flex-1 min-w-0">{body}</div>;
})
