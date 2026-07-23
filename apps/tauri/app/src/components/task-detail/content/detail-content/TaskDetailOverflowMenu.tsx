import {
  useCallback,
  useEffect,
  useId,
  useLayoutEffect,
  useRef,
  useState,
  type KeyboardEvent,
} from 'react';
import { createPortal } from 'react-dom';

import type { TaskDetailControllerState } from '@/components/task-detail/support';
import { CheckIcon, ClipboardIcon, TrashIcon, XIcon } from '@/components/ui/icons';
import { Tooltip } from '@/components/ui/Tooltip';
import {
  createBrowserAnchoredPopupDismissRuntimeDeps,
  installAnchoredPopupDismissRuntime,
  resolveAnchoredPopupPosition,
} from '@/components/ui/portalDropdown.runtime';
import {
  focusTaskDetailOverflowMenuItem,
  resolveTaskDetailOverflowKeyAction,
} from './TaskDetailOverflowMenu.runtime';
import { TASK_STATUS } from '@lorvex/shared/types';

export function TaskDetailOverflowMenu({
  controller,
  isActionable,
  isComplete,
  task,
  t,
}: {
  controller: TaskDetailControllerState;
  isActionable: boolean;
  isComplete: boolean;
  task: NonNullable<TaskDetailControllerState['task']>;
  t: TaskDetailControllerState['t'];
}) {
  const [overflowOpen, setOverflowOpen] = useState(false);
  const [overflowPos, setOverflowPos] = useState<{ top: number; left: number } | null>(null);
  const overflowMenuId = useId();
  const overflowTriggerRef = useRef<HTMLButtonElement | null>(null);
  const overflowPanelRef = useRef<HTMLDivElement | null>(null);
  const overflowWasOpenRef = useRef(false);
  const updateOverflowPosition = useCallback(() => {
    if (!overflowTriggerRef.current) { setOverflowPos(null); return; }
    const rect = overflowTriggerRef.current.getBoundingClientRect();
    setOverflowPos(resolveAnchoredPopupPosition({
      rect,
      viewportWidth: window.innerWidth,
      viewportHeight: window.innerHeight,
      popupWidth: 192,
      popupHeight: overflowPanelRef.current?.offsetHeight,
      flipVertically: true,
      horizontalAlign: 'end',
    }));
  }, []);
  const setOverflowPanelNode = useCallback((node: HTMLDivElement | null) => {
    overflowPanelRef.current = node;
    if (node) updateOverflowPosition();
  }, [updateOverflowPosition]);
  const getEnabledOverflowMenuItems = useCallback(() => {
    const panel = overflowPanelRef.current;
    if (!panel) return [];
    return Array.from(
      panel.querySelectorAll<HTMLButtonElement>('[role="menuitem"]:not(:disabled)'),
    );
  }, []);
  const focusOverflowMenuItem = useCallback((index: number) => {
    const items = getEnabledOverflowMenuItems();
    focusTaskDetailOverflowMenuItem({
      items,
      panel: overflowPanelRef.current,
      index,
    });
  }, [getEnabledOverflowMenuItems]);
  const focusFirstOverflowMenuItem = useCallback(() => {
    focusOverflowMenuItem(0);
  }, [focusOverflowMenuItem]);
  const handleOverflowPanelKeyDown = useCallback((event: KeyboardEvent<HTMLDivElement>) => {
    const items = getEnabledOverflowMenuItems();
    const currentIndex = items.indexOf(document.activeElement as HTMLButtonElement);
    const action = resolveTaskDetailOverflowKeyAction({
      key: event.key,
      currentIndex,
      itemCount: items.length,
    });
    if (action.type === 'close') {
      event.preventDefault();
      event.stopPropagation();
      setOverflowOpen(false);
      overflowTriggerRef.current?.focus();
      return;
    }
    if (action.type === 'focus') {
      event.preventDefault();
      focusOverflowMenuItem(action.index);
    }
  }, [focusOverflowMenuItem, getEnabledOverflowMenuItems]);

  useEffect(() => {
    setOverflowOpen(false);
  }, [task.id]);

  useEffect(() => {
    if (overflowOpen) {
      overflowWasOpenRef.current = true;
      return;
    }
    if (!overflowWasOpenRef.current) return;
    overflowWasOpenRef.current = false;
    overflowTriggerRef.current?.focus();
  }, [overflowOpen]);

  useLayoutEffect(() => {
    if (!overflowOpen) { setOverflowPos(null); return; }
    updateOverflowPosition();
  }, [overflowOpen, updateOverflowPosition]);

  useEffect(() => {
    if (!overflowOpen || !overflowPos) return;
    const frame = window.requestAnimationFrame(focusFirstOverflowMenuItem);
    return () => window.cancelAnimationFrame(frame);
  }, [focusFirstOverflowMenuItem, overflowOpen, overflowPos]);

  useEffect(() => {
    if (!overflowOpen) return;
    const dismiss = () => setOverflowOpen(false);
    return installAnchoredPopupDismissRuntime(createBrowserAnchoredPopupDismissRuntimeDeps({
      documentTarget: document,
      windowTarget: window,
      getTrigger: () => overflowTriggerRef.current,
      getPanel: () => overflowPanelRef.current,
      onPointerDismiss: dismiss,
      onScrollDismiss: dismiss,
      onEscapeDismiss: dismiss,
      onResizeDismiss: dismiss,
      listenForScroll: true,
      listenForEscape: true,
      listenForResize: true,
      pointerEventType: 'pointerdown',
    }));
  }, [overflowOpen]);

  return (
    <div className="relative">
      <Tooltip label={t('common.actions')}>
        <button
          ref={overflowTriggerRef}
          type="button"
          onClick={() => setOverflowOpen(!overflowOpen)}
          className="text-text-muted/60 hover:text-text-primary hover:bg-surface-2/50 transition-colors duration-150 rounded-r-control focus-ring-soft w-7 h-7 flex items-center justify-center"
          aria-label={t('common.actions')}
          aria-haspopup="menu"
          aria-expanded={overflowOpen}
          aria-controls={overflowOpen ? overflowMenuId : undefined}
        >
          <svg width="14" height="14" viewBox="0 0 16 16" fill="currentColor">
            <circle cx="4" cy="8" r="1.3" />
            <circle cx="8" cy="8" r="1.3" />
            <circle cx="12" cy="8" r="1.3" />
          </svg>
        </button>
      </Tooltip>
      {overflowOpen && overflowPos && createPortal(
        <div
          id={overflowMenuId}
          ref={setOverflowPanelNode}
          className="fixed min-w-[var(--menu-min-w-lg)] bg-surface-1 border border-card rounded-r-panel shadow-[var(--shadow-popover)] py-1 z-[var(--z-popover)] animate-[slide-in-up_0.15s_ease-out]"
          style={{ top: overflowPos.top, left: overflowPos.left }}
          role="menu"
          aria-orientation="vertical"
          aria-label={t('common.actions')}
          tabIndex={-1}
          onKeyDown={handleOverflowPanelKeyDown}
        >
          <OverflowMenuItem
            icon={<ClipboardIcon className="w-3.5 h-3.5" />}
            label={t('task.duplicate')}
            disabled={controller.actionPending}
            onClick={() => { void controller.handleDuplicate(); setOverflowOpen(false); }}
          />
          {(isComplete || task.status === TASK_STATUS.cancelled) && (
            <OverflowMenuItem
              icon={<CheckIcon className="w-3.5 h-3.5" />}
              label={t('task.reopen')}
              disabled={controller.actionPending}
              onClick={() => { void controller.handleReopen(); setOverflowOpen(false); }}
            />
          )}
          {task.defer_count > 0 && (
            <OverflowMenuItem
              icon={<svg className="w-3.5 h-3.5" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"><path d="M2 8a6 6 0 1 1 1.76 4.24" /><path d="M2 12V8h4" /></svg>}
              label={t('task.resetDeferral')}
              disabled={controller.actionPending}
              onClick={() => { void controller.handleResetDeferral(); setOverflowOpen(false); }}
            />
          )}
          {(isActionable || task.status === TASK_STATUS.cancelled) && (
            <div className="mx-2 my-1 border-t border-card" role="separator" />
          )}
          {isActionable && !task.recurrence && (
            <OverflowMenuItem
              icon={<XIcon className="w-3.5 h-3.5" />}
              label={t('task.cancel')}
              disabled={controller.actionPending}
              variant="danger"
              onClick={() => { void controller.handleDelete(); setOverflowOpen(false); }}
            />
          )}
          <OverflowMenuItem
            icon={<TrashIcon className="w-3.5 h-3.5" />}
            label={t('task.deletePermanent')}
            disabled={controller.actionPending}
            variant="danger"
            onClick={() => { void controller.handlePermanentDelete(); setOverflowOpen(false); }}
          />
        </div>,
        document.body,
      )}
    </div>
  );
}

function OverflowMenuItem({
  icon,
  label,
  disabled = false,
  variant,
  onClick,
}: {
  icon: React.ReactNode;
  label: string;
  disabled?: boolean;
  variant?: 'danger';
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      role="menuitem"
      tabIndex={-1}
      onClick={onClick}
      disabled={disabled}
      className={`flex items-center gap-2 w-full text-start px-3 py-1.5 text-xs transition-colors focus-ring-soft rounded-r-control ${
        variant === 'danger'
          ? 'text-danger/70 hover:bg-[var(--danger-tint-xs)] hover:text-danger'
          : 'text-text-secondary hover:bg-surface-2/60 hover:text-text-primary'
      } disabled:opacity-40 disabled:cursor-not-allowed`}
    >
      <span className="shrink-0">{icon}</span>
      {label}
    </button>
  );
}
