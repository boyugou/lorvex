import { memo, useCallback, useEffect, useRef } from 'react';
import { ContextMenu } from '../context-menu/ContextMenu';
import { useLongPress } from '@/lib/useLongPress';
import { TaskCardActionButton } from './TaskCardActionButton';
import { TaskCardContent } from './TaskCardContent';
import { TaskCardQuickActions } from './TaskCardQuickActions';
import type { TaskCardProps } from './support';
import { useTaskCardController } from './useTaskCardController';
import { useTaskContextMenu } from './useTaskContextMenu';

export default memo(function TaskCard({
  task,
  rank,
  completed = false,
  disableComplete = false,
  focused = false,
  selected = false,
  hideListInfo = false,
  showListColor = true,
  onClick,
  onKeyDown,
  taskButtonRole,
  taskButtonAriaChecked,
  taskButtonAriaLabel,
  taskButtonAriaDescription,
  taskButtonAriaRoleDescription,
  taskButtonAriaKeyShortcuts,
  taskButtonDisabled,
  hideQuickActions = false,
}: TaskCardProps) {
  const rootRef = useRef<HTMLDivElement>(null);
  const {
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
  } = useTaskCardController({
    task,
    completed,
    disableComplete,
  });
  const isClickable = !!onClick;
  const contextMenu = useTaskContextMenu(task);

  // Listen for external "start editing" signal (e.g. keyboard shortcut 'e')
  useEffect(() => {
    const el = rootRef.current;
    if (!el) return;
    const handler = () => {
      if (!isDone) setIsEditingTitle(true);
    };
    el.addEventListener('lorvex:start-edit-title', handler);
    return () => el.removeEventListener('lorvex:start-edit-title', handler);
  }, [isDone, setIsEditingTitle]);

  // Listen for external "open context menu" signal (e.g. keyboard shortcut '.' or Shift+F10)
  useEffect(() => {
    const el = rootRef.current;
    if (!el) return;
    const handler = () => {
      const rect = el.getBoundingClientRect();
      // Position the menu near the right side of the card, vertically centered
      contextMenu.openAt(rect.right - 40, rect.top + rect.height / 2, el);
    };
    el.addEventListener('lorvex:open-context-menu', handler);
    return () => el.removeEventListener('lorvex:open-context-menu', handler);
  }, [contextMenu]);

  const handleLongPress = useCallback((x: number, y: number) => {
    contextMenu.openAt(x, y, rootRef.current);
  }, [contextMenu]);
  const longPress = useLongPress(handleLongPress);

  return (
    // The card root carries onContextMenu (right-click) and onTouch*
    // (long-press) for the context menu — both have native keyboard
    // equivalents (the OS's ContextMenu / Shift+F10 key fires
    // onContextMenu directly). The primary actions live on inner
    // buttons (mark-done, open detail), and per the H3 a11y review
    // the card itself uses `aria-current` rather than acting as a
    // selectable composite. No additional onKeyDown contract belongs
    // here.
    // eslint-disable-next-line jsx-a11y/no-static-element-interactions
    <div
      ref={rootRef}
      data-task-id={task.id}
      // The previous `aria-selected` only carries
      // semantics inside an explicit listbox/grid/tablist composite.
      // None of the parents that render TaskCard (today list, kanban
      // column, eisenhower quadrant, somdeay rail, etc.) use those
      // roles, so AT consumers got "selected" announced on a bare
      // div with no container role to interpret it. `aria-current`
      // works on any element and conveys the same "this is the row
      // the master/detail panel is reflecting" meaning.
      aria-current={selected ? 'true' : undefined}
      className={`cv-task-card @container group flex items-center gap-3 px-4 py-3 rounded-r-card border transition-[background-color,border-color,opacity,transform,box-shadow] duration-200 ${
        focused
          ? 'bg-surface-3 border-accent/40 ring-1 ring-accent/20'
          : selected
            ? 'bg-accent/10 border-accent/40 ring-1 ring-accent/25 shadow-[var(--shadow-tooltip)]'
            : isDone
              ? 'bg-[var(--success-tint-sm)] border-success/30 opacity-60 scale-[0.98]'
              : completing
                // begin the row settle during the
                // optimistic-complete window so the opacity/scale
                // glide overlaps with the checkmark stroke draw + the
                // title strikethrough sweep — the whole gesture
                // resolves as one confident sequence, not three
                // simultaneous flips.
                ? 'bg-surface-2 border-transparent opacity-50 scale-[0.98]'
                : isClickable
                  ? 'bg-surface-2 border-transparent hover:bg-surface-3 hover:border-surface-3 hover:shadow-[var(--shadow-tooltip)]'
                  : 'bg-surface-2 border-transparent'
      }`}
      style={showListColor && !focused && !isDone && !hideListInfo && listInfo?.color ? {
        borderInlineStartColor: listInfo.color,
        borderInlineStartWidth: '3px',
      } : undefined}
      onContextMenu={contextMenu.onContextMenu}
      onTouchStart={longPress.onTouchStart}
      onTouchEnd={longPress.onTouchEnd}
      onTouchMove={longPress.onTouchMove}
    >
      <div className="shrink-0">
        <TaskCardActionButton
          rank={rank}
          isDone={isDone}
          canQuickReopen={canQuickReopen}
          disableComplete={disableComplete}
          completing={completing}
          reopening={reopening}
          labels={labels}
          onComplete={handleComplete}
          onReopen={handleReopen}
        />
      </div>

      <TaskCardContent
        task={task}
        isDone={isDone}
        completing={completing}
        dueDateStr={dueDateStr}
        overdue={overdue}
        dueToday={dueToday}
        bodySnippet={bodySnippet}
        tags={tags}
        checklistProgress={checklistProgress}
        labels={labels}
        listInfo={hideListInfo ? null : listInfo}
        onClick={onClick}
        onKeyDown={onKeyDown}
        taskButtonRole={taskButtonRole}
        taskButtonAriaChecked={taskButtonAriaChecked}
        taskButtonAriaLabel={taskButtonAriaLabel}
        taskButtonAriaDescription={taskButtonAriaDescription}
        taskButtonAriaRoleDescription={taskButtonAriaRoleDescription}
        taskButtonAriaKeyShortcuts={taskButtonAriaKeyShortcuts}
        taskButtonDisabled={taskButtonDisabled}
        isEditingTitle={isEditingTitle}
        isSavingTitle={isSavingTitle}
        onStartEditTitle={() => setIsEditingTitle(true)}
        onTitleSave={handleTitleSave}
        onTitleCancel={() => setIsEditingTitle(false)}
      />

      {!hideQuickActions && !isDone && !isEditingTitle && !isSavingTitle && (
        <TaskCardQuickActions task={task} />
      )}

      {contextMenu.isOpen && (
        <ContextMenu
          items={contextMenu.items}
          position={contextMenu.position}
          onClose={contextMenu.close}
          triggerElement={contextMenu.triggerElement}
        />
      )}
    </div>
  );
  // No custom equality: React's default shallow `===` check over
  // every prop is what `memo` does without an equality function. The
  // hot-path props (`task`, `onClick`, `onKeyDown`) are already
  // memoized at the call site, so the steady-state behaviour stays
  // identical to a hand-tuned comparator while the stale-skip class
  // of bug (a sibling write touching `title`, `tags`, `checklist`,
  // `due_date`, `priority`, `estimated_minutes`, `body`, `list_id`,
  // or `status` without bumping `updated_at` — FTS projection
  // repairs, tag-membership migrations, optimistic cache patches —
  // is structurally impossible.
});
