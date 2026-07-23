import { createElement } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import { CheckIcon, FlagIcon } from '../ui/icons';
import type { ContextMenuItem } from '../context-menu/ContextMenu';
import type { TranslationKey } from '@/lib/i18n';
import type { ActionHelpers } from './types';
import { PRIORITY_NUMERIC_OPTIONS } from './support';

type TFn = (key: TranslationKey) => string;

/** Build the "Priority" submenu items. Current priority is shown with a checkmark and disabled. */
export function buildPriorityMenuItem(
  task: Task,
  t: TFn,
  helpers: Pick<ActionHelpers, 'runUpdate'>,
): ContextMenuItem {
  const submenu: ContextMenuItem[] = PRIORITY_NUMERIC_OPTIONS.map((p) => {
    const isCurrent = p.value === task.priority;
    return {
      key: `priority-${p.value}`,
      label: t(p.labelKey),
      icon: isCurrent
        ? createElement(CheckIcon, { className: 'w-3.5 h-3.5' })
        : createElement(FlagIcon, { className: 'w-3.5 h-3.5' }),
      disabled: isCurrent,
      onSelect: isCurrent
        ? undefined
        : () => helpers.runUpdate(
            { priority: p.value },
            'contextMenu.priority', 'Failed to update priority',
            t(p.labelKey),
          ),
    };
  });

  // Separator + Clear option
  const isClear = task.priority == null;
  submenu.push(
    { key: 'priority-sep', label: '', separator: true },
    {
      key: 'priority-none',
      label: t('task.noPriority'),
      icon: isClear
        ? createElement(CheckIcon, { className: 'w-3.5 h-3.5' })
        : undefined,
      disabled: isClear,
      onSelect: isClear
        ? undefined
        : () => helpers.runUpdate(
            { priority: null },
            'contextMenu.priority', 'Failed to update priority',
            t('task.noPriority'),
          ),
    },
  );

  return {
    key: 'priority',
    label: t('task.priority'),
    icon: createElement(FlagIcon, { className: 'w-3.5 h-3.5' }),
    submenu,
  };
}
