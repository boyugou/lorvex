import {
  useCallback,
  useEffect,
  useId,
  useMemo,
  useRef,
  useState,
  type CSSProperties,
  type KeyboardEvent as ReactKeyboardEvent,
  type MouseEvent as ReactMouseEvent,
} from 'react';
import { createPortal } from 'react-dom';
import type { Task } from '@/lib/ipc/tasks/models';
import type { TranslationKey } from '@/lib/i18n';
import { CheckIcon } from '../ui/icons';
import {
  computeCompletedTasksPopoverPosition,
  restoreCompletedTasksPopoverTriggerFocus,
  scheduleCompletedTasksPopoverInitialFocus,
  shouldDismissCompletedTasksPopoverFromKeyEvent,
  type CompletedTasksPopoverFocusHost,
  type CompletedTasksPopoverPosition,
} from './completedTasksPopover.runtime';
import {
  createBrowserAnchoredPopupDismissRuntimeDeps,
  installAnchoredPopupDismissRuntime,
} from '../ui/portalDropdown.runtime';
import { getPopoverLayerClasses } from '../ui/popoverLayer';

/**
 * Completed-task count chip plus anchored dialog. Kept separate from the
 * week-cell renderer because it owns focus restoration, portal positioning,
 * outside-click dismissal, and task selection.
 */
export function CompletedTasksPopover({
  count,
  tasks,
  formatNumber,
  onSelectTask,
  t,
}: {
  count: number;
  tasks: Task[];
  formatNumber: (value: number) => string;
  onSelectTask: (id: string) => void;
  t: (key: TranslationKey) => string;
}) {
  const [open, setOpen] = useState(false);
  const [position, setPosition] = useState<CompletedTasksPopoverPosition | null>(null);
  const popoverId = useId();
  const triggerRef = useRef<HTMLButtonElement>(null);
  const popoverRef = useRef<HTMLDivElement>(null);
  const itemRefs = useRef<Array<HTMLButtonElement | null>>([]);
  const focusHost = useMemo<CompletedTasksPopoverFocusHost>(() => ({
    requestAnimationFrame: (callback) => {
      if (typeof window === 'undefined') {
        callback(0);
        return 0;
      }
      return window.requestAnimationFrame(callback);
    },
    cancelAnimationFrame: (handle) => {
      if (typeof window === 'undefined') return;
      window.cancelAnimationFrame(handle);
    },
  }), []);
  const portalTarget = typeof document === 'undefined' ? null : document.body;
  const layerClasses = getPopoverLayerClasses('popover');

  const updatePosition = useCallback(() => {
    const trigger = triggerRef.current;
    if (!trigger || typeof window === 'undefined') return;
    const triggerRect = trigger.getBoundingClientRect();
    const popoverRect = popoverRef.current?.getBoundingClientRect();
    setPosition(computeCompletedTasksPopoverPosition({
      triggerRect,
      popoverSize: {
        width: popoverRect?.width || 220,
        height: popoverRect?.height || 192,
      },
      viewport: {
        width: window.innerWidth,
        height: window.innerHeight,
      },
    }));
  }, []);

  const closePopover = useCallback((restoreFocus: boolean) => {
    setOpen(false);
    setPosition(null);
    if (!restoreFocus) return;
    restoreCompletedTasksPopoverTriggerFocus(focusHost, () => triggerRef.current);
  }, [focusHost]);

  useEffect(() => {
    if (!open) return;
    updatePosition();
    if (typeof window === 'undefined') return undefined;
    const frame = window.requestAnimationFrame(updatePosition);
    window.addEventListener('resize', updatePosition);
    window.addEventListener('scroll', updatePosition, true);
    return () => {
      window.cancelAnimationFrame(frame);
      window.removeEventListener('resize', updatePosition);
      window.removeEventListener('scroll', updatePosition, true);
    };
  }, [open, updatePosition]);

  useEffect(() => {
    if (!open) return;
    return installAnchoredPopupDismissRuntime(
      createBrowserAnchoredPopupDismissRuntimeDeps({
        getTrigger: () => triggerRef.current,
        getPanel: () => popoverRef.current,
        onEscapeDismiss: () => closePopover(true),
        onPointerDismiss: () => closePopover(false),
        listenForEscape: true,
      }),
    );
  }, [closePopover, open]);

  useEffect(() => {
    if (!open) return;
    return scheduleCompletedTasksPopoverInitialFocus(
      focusHost,
      () => {
        const panel = popoverRef.current;
        return {
          panel,
          firstItem: itemRefs.current[0] ?? null,
          activeElement: typeof document === 'undefined' ? null : document.activeElement,
          isActiveElementInPanel: (activeElement) => (
            typeof HTMLElement !== 'undefined'
            && activeElement instanceof HTMLElement
            && panel !== null
            && panel.contains(activeElement)
            && activeElement !== panel
          ),
        };
      },
    );
  }, [focusHost, open]);

  const handleTriggerClick = useCallback((event: ReactMouseEvent<HTMLButtonElement>) => {
    event.stopPropagation();
    if (open) {
      closePopover(false);
      return;
    }
    setOpen(true);
    setPosition(null);
  }, [closePopover, open]);

  const handleTriggerKeyDown = useCallback((event: ReactKeyboardEvent<HTMLButtonElement>) => {
    if (!open || !shouldDismissCompletedTasksPopoverFromKeyEvent(event)) return;
    event.preventDefault();
    event.stopPropagation();
    closePopover(true);
  }, [closePopover, open]);

  const handlePopoverKeyDown = useCallback((event: ReactKeyboardEvent<HTMLDivElement>) => {
    if (!shouldDismissCompletedTasksPopoverFromKeyEvent(event)) return;
    event.preventDefault();
    event.stopPropagation();
    closePopover(true);
  }, [closePopover]);

  const popoverStyle: CSSProperties = position
    ? {
        top: position.top,
        left: position.left,
        width: position.width,
        maxHeight: position.maxHeight,
      }
    : {
        top: 0,
        left: 0,
        width: 220,
        maxHeight: 192,
        visibility: 'hidden',
      };

  const popover = open && portalTarget ? createPortal(
    <div
      ref={popoverRef}
      id={popoverId}
      role="dialog"
      tabIndex={-1}
      aria-label={t('calendar.completedTodayLabel')}
      onKeyDown={handlePopoverKeyDown}
      className={`fixed ${layerClasses.panel} rounded-r-control border border-card bg-surface-1 shadow-[var(--shadow-popover)] py-1 overflow-y-auto`}
      style={popoverStyle}
    >
      {tasks.map((task, index) => (
        <button
          key={task.id}
          ref={(node) => {
            itemRefs.current[index] = node;
          }}
          type="button"
          onClick={(event) => {
            event.stopPropagation();
            closePopover(false);
            onSelectTask(task.id);
          }}
          className="block w-full text-start px-2 py-1 text-2xs text-text-secondary hover:bg-surface-2 hover:text-text-primary transition-colors line-through decoration-text-muted/40 focus-ring-soft rounded-r-control"
        >
          <span className="truncate block">{task.title}</span>
        </button>
      ))}
    </div>,
    portalTarget,
  ) : null;

  return (
    <div className="relative">
      <button
        ref={triggerRef}
        type="button"
        onClick={handleTriggerClick}
        onKeyDown={handleTriggerKeyDown}
        aria-haspopup="dialog"
        aria-expanded={open}
        aria-controls={open ? popoverId : undefined}
        aria-label={t('calendar.completedTodayLabel')}
        className="w-full flex items-center gap-1 px-2 py-1 mt-0.5 rounded-r-control chip-success-subtle chip-success-interactive text-2xs font-medium active:scale-[0.97] focus-ring-soft-success"
      >
        <CheckIcon className="w-2.5 h-2.5 shrink-0" />
        <span className="tabular-nums">{formatNumber(count)}</span>
      </button>
      {popover}
    </div>
  );
}
