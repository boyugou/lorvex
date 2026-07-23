import { createElement, useCallback, useMemo, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';

import type { Task } from '@/lib/ipc/tasks/models';
import type { TaskUpdatePatch } from '@/lib/ipc/tasks/mutations/types';
import { getAllLists } from '@/lib/ipc/tasks/lists';
import { archiveTask, cancelTask, completeTask, reopenTask } from '@/lib/ipc/tasks/mutations/lifecycle';
import { duplicateTask, updateTask } from '@/lib/ipc/tasks/mutations/quickCapture';
import { isTaskActive } from '@/lib/format';
import { showUndoToastWithRedo } from '@/lib/tasks/lifecycleUndoRedo';
import { STALE_DEFAULT } from '@/lib/query/timing';
import { useDayContext } from '@/lib/DayContextProvider';
import { confirm } from '@/lib/dialogs/confirm';
import { reportClientError } from '@/lib/errors/errorLogging';
import { toast } from '@/lib/notifications/toast';
import { useI18n } from '@/lib/i18n';
import { useCopyToClipboard } from '@/lib/platform/useCopyToClipboard';
import { QUERY_KEYS, invalidateTaskMutationQueries } from '@/lib/query/queryKeys';
import type { ContextMenuItem, ContextMenuPosition } from '../context-menu/ContextMenu';
import {
  ArrowRightIcon,
  CheckIcon,
  ClipboardIcon,
  ExternalIcon,
  PlayIcon,
  TrashIcon,
  UndoIcon,
  XIcon,
} from '../ui/icons';

import { buildDeferMenuItems, buildDueDateMenuItem } from './deferPresets';
import { buildPriorityMenuItem } from './priorityMenuItems';
import { buildDurationMenuItem, buildMoveToListMenuItem, buildRecurrenceMenuItem } from './fieldSubmenus';
import { TASK_STATUS } from '@lorvex/shared/types';

interface TaskContextMenuState {
  isOpen: boolean;
  position: ContextMenuPosition;
  triggerElement: HTMLElement | null;
  items: ContextMenuItem[];
  onContextMenu: (e: React.MouseEvent) => void;
  openAt: (x: number, y: number, triggerElement?: HTMLElement | null) => void;
  close: () => void;
}

export function useTaskContextMenu(task: Task): TaskContextMenuState {
  const { t } = useI18n();
  const { copy } = useCopyToClipboard();
  const qc = useQueryClient();
  const dayContext = useDayContext();
  const [isOpen, setIsOpen] = useState(false);
  const [position, setPosition] = useState<ContextMenuPosition>({ x: 0, y: 0 });
  const [triggerElement, setTriggerElement] = useState<HTMLElement | null>(null);

  const { data: lists = [] } = useQuery({
    queryKey: QUERY_KEYS.lists(),
    queryFn: ({ signal }) => getAllLists(signal),
    staleTime: STALE_DEFAULT,
    enabled: isOpen,
  });

  const onContextMenu = useCallback((e: React.MouseEvent) => {
    e.preventDefault();
    e.stopPropagation();
    setPosition({ x: e.clientX, y: e.clientY });
    setTriggerElement(e.currentTarget instanceof HTMLElement ? e.currentTarget : null);
    setIsOpen(true);
  }, []);

  const openAt = useCallback((x: number, y: number, trigger: HTMLElement | null = null) => {
    setPosition({ x, y });
    setTriggerElement(trigger);
    setIsOpen(true);
  }, []);

  const close = useCallback(() => {
    setIsOpen(false);
    setTriggerElement(null);
  }, []);

  const invalidate = useCallback(
    (listId?: string | null) => {
      invalidateTaskMutationQueries(qc, { listId });
    },
    [qc],
  );

  const isActive = isTaskActive(task.status);
  const isDone = task.status === TASK_STATUS.completed || task.status === TASK_STATUS.cancelled;

  const items = useMemo<ContextMenuItem[]>(() => {
    // -- shared helpers (closed over task + invalidate) --

    const catchError = (source: string, message: string) =>
      (err: unknown) => reportClientError(source, message, err);

    const runAction = (
      action: Promise<unknown>,
      source: string,
      errorMessage: string,
      successToast?: string,
      extraListIds?: Array<string | null | undefined>,
    ) => {
      void action
        .then(() => {
          invalidate(task.list_id);
          if (extraListIds) extraListIds.forEach((id) => invalidate(id));
          if (successToast) toast.success(successToast);
        })
        .catch(catchError(source, errorMessage));
    };

    const runUpdate = (
      updates: TaskUpdatePatch,
      source: string,
      errorMessage: string,
      successToast?: string,
    ) => runAction(updateTask(task.id, updates), source, errorMessage, successToast);

    const helpers = { runAction, runUpdate, invalidate };
    const result: ContextMenuItem[] = [];

    // Complete / Reopen
    if (isActive) {
      result.push({
        key: 'complete',
        label: t('task.complete'),
        icon: createElement(CheckIcon, { className: 'w-3.5 h-3.5' }),
        onSelect: () => {
          void completeTask(task.id)
            .then((result) => {
              invalidate(task.list_id);
              showUndoToastWithRedo(t('task.status.completed'), result.undo_token, {
                invalidate: () => invalidate(task.list_id),
                t,
                errorKeyPrefix: 'contextMenu.complete',
              });
            })
            .catch(catchError('contextMenu.complete', 'Failed to complete task'));
        },
      });
    }
    if (isDone) {
      result.push({
        key: 'reopen',
        label: t('task.reopen'),
        icon: createElement(UndoIcon, { className: 'w-3.5 h-3.5' }),
        onSelect: () => runAction(
          reopenTask(task.id),
          'contextMenu.reopen', 'Failed to reopen task',
          t('task.reopen'),
        ),
      });
    }

    // Promote to active (for someday tasks)
    if (task.status === TASK_STATUS.someday) {
      result.push({
        key: 'promote',
        label: t('contextMenu.promoteToActive'),
        icon: createElement(PlayIcon, { className: 'w-3.5 h-3.5' }),
        onSelect: () => runUpdate(
          { status: 'open' },
          'contextMenu.promote', 'Failed to promote task',
          t('task.promoted'),
        ),
      });
    }

    // Submenus (only for active tasks)
    if (isActive) {
      result.push(buildDeferMenuItems(task, dayContext, t, helpers));
      result.push(buildDueDateMenuItem(task, dayContext, t, runUpdate));
      result.push(buildRecurrenceMenuItem(task, t, runUpdate));
      result.push(buildDurationMenuItem(task, t, runUpdate));
      result.push(buildPriorityMenuItem(task, t, helpers));

      // Move to list
      if (lists.length > 0) {
        const moveItem = buildMoveToListMenuItem(task, lists, t, helpers);
        if (moveItem) result.push(moveItem);
      }

      // Duplicate
      result.push({
        key: 'duplicate',
        label: t('task.duplicate'),
        icon: createElement(ExternalIcon, { className: 'w-3.5 h-3.5' }),
        onSelect: () => runAction(
          duplicateTask(task.id),
          'contextMenu.duplicate', 'Failed to duplicate task',
          t('task.duplicated'),
        ),
      });

    }

    // Copy task ID
    result.push({
      key: 'copy-id',
      label: t('task.copyId'),
      icon: createElement(ClipboardIcon, { className: 'w-3.5 h-3.5' }),
      onSelect: () => {
        void copy(task.id, t('task.copiedId'));
      },
    });

    // Separator before destructive actions
    if (result.length > 0) {
      result.push({ key: 'sep-1', label: '', separator: true });
    }

    // Cancel (for active tasks)
    if (isActive) {
      const isRecurring = !!task.recurrence;
      if (isRecurring) {
        // For recurring tasks, show a submenu with skip/stop options.
        result.push({
          key: 'cancel',
          label: t('task.cancel'),
          icon: createElement(XIcon, { className: 'w-3.5 h-3.5' }),
          danger: true,
          submenu: [
            {
              key: 'cancel-skip',
              label: t('task.cancelRecurringSkip'),
              icon: createElement(ArrowRightIcon, { className: 'w-3.5 h-3.5' }),
              onSelect: () => {
                void cancelTask(task.id, false)
                  .then((result) => {
                    invalidate(task.list_id);
                    showUndoToastWithRedo(t('task.status.cancelled'), result.undo_token, {
                      invalidate: () => invalidate(task.list_id),
                      t,
                      errorKeyPrefix: 'contextMenu.cancelSkip',
                    });
                  })
                  .catch(catchError('contextMenu.cancel', 'Failed to cancel task'));
              },
            },
            {
              key: 'cancel-series',
              label: t('task.cancelRecurringSeries'),
              icon: createElement(XIcon, { className: 'w-3.5 h-3.5 text-danger' }),
              danger: true,
              onSelect: () => {
                void cancelTask(task.id, true)
                  .then((result) => {
                    invalidate(task.list_id);
                    showUndoToastWithRedo(t('task.status.cancelled'), result.undo_token, {
                      invalidate: () => invalidate(task.list_id),
                      t,
                      errorKeyPrefix: 'contextMenu.cancelSeries',
                    });
                  })
                  .catch(catchError('contextMenu.cancel', 'Failed to cancel task'));
              },
            },
          ],
        });
      } else {
        result.push({
          key: 'cancel',
          label: t('task.cancel'),
          icon: createElement(XIcon, { className: 'w-3.5 h-3.5' }),
          danger: true,
          onSelect: () => {
            void confirm({
              title: t('task.cancel'),
              message: t('task.confirmCancel'),
              variant: 'danger',
              confirmLabel: t('task.cancel'),
            }).then((confirmed) => {
              if (!confirmed) return;
              void cancelTask(task.id)
                .then((result) => {
                  invalidate(task.list_id);
                  showUndoToastWithRedo(t('task.status.cancelled'), result.undo_token, {
                    invalidate: () => invalidate(task.list_id),
                    t,
                    errorKeyPrefix: 'contextMenu.cancel',
                  });
                })
                .catch(catchError('contextMenu.cancel', 'Failed to cancel task'));
            });
          },
        });
      }
    }

    // Delete (for cancelled tasks) — routes through Trash. so
    // the user has 30 days to undo. The `permanentDeleteTask` endpoint
    // now rejects non-archived tasks; the Trash view is the only place
    // that hard-deletes.
    if (task.status === TASK_STATUS.cancelled) {
      result.push({
        key: 'delete',
        label: t('task.move_to_trash'),
        icon: createElement(TrashIcon, { className: 'w-3.5 h-3.5' }),
        danger: true,
        onSelect: () => {
          void confirm({
            title: t('task.move_to_trash'),
            message: t('task.confirmPermanentDelete'),
            variant: 'danger',
            confirmLabel: t('task.move_to_trash'),
          }).then((confirmed) => {
            if (!confirmed) return;
            runAction(
              archiveTask(task.id),
              'contextMenu.archive', 'Failed to move task to Trash',
            );
          });
        },
      });
    }

    return result;
  }, [copy, dayContext, invalidate, isActive, isDone, lists, t, task]);

  // Stabilize the returned object so consumers depending on
  // `contextMenu` (e.g. TaskCard's "open context menu" listener
  // effect) don't re-attach event listeners on every render. Each
  // primitive field is already stable: `onContextMenu`, `openAt`, and
  // `close` are `useCallback`s above, and `items` is a `useMemo`.
  return useMemo(
    () => ({ isOpen, position, triggerElement, items, onContextMenu, openAt, close }),
    [isOpen, position, triggerElement, items, onContextMenu, openAt, close],
  );
}
