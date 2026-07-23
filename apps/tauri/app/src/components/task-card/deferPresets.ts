import { createElement } from 'react';

import type { DayContext } from '@/lib/dayContext';
import {
  getNextMondayYmd,
  getNextWeekendYmd,
} from '@/lib/dayContextMath';
import {
  getRelativeDateYmd,
} from '@/lib/dayContext';
import { DEFER_REASON_NOT_TODAY } from '@lorvex/shared/types';
import type { Task } from '@/lib/ipc/tasks/models';
import { deferTaskUntil } from '@/lib/ipc/tasks/mutations/deferral';
import { runTaskDeferralWithUndo } from '@/lib/tasks/deferralUndo';
import { buildDueDatePatch } from '@/lib/tasks/dueAtPatch.logic';
import { CalendarDayIcon, ClockIcon } from '../ui/icons';
import type { ContextMenuItem } from '../context-menu/ContextMenu';
import type { TranslationKey } from '@/lib/i18n';
import { buildUpdateSubmenu } from './buildUpdateSubmenu';
import type { ActionHelpers, RunUpdate } from './types';

// ─── Types ───────────────────────────────────────────────────────────────────

type TFn = (key: TranslationKey) => string;

// ─── Preset builders (pure) ─────────────────────────────────────────────────

function buildDeferPresets(dayContext: DayContext) {
  return [
    { key: 'defer-tomorrow', labelKey: 'task.defer.tomorrow' as TranslationKey, date: dayContext.tomorrowYmd },
    { key: 'defer-weekend', labelKey: 'task.defer.weekend' as TranslationKey, date: getNextWeekendYmd(dayContext.timezone) },
    { key: 'defer-nextweek', labelKey: 'task.defer.nextWeek' as TranslationKey, date: getNextMondayYmd(dayContext.timezone) },
    { key: 'defer-twoweeks', labelKey: 'task.defer.twoWeeks' as TranslationKey, date: getRelativeDateYmd(dayContext.timezone, 14) },
    { key: 'defer-someday', labelKey: 'task.defer.someday' as TranslationKey, date: null as string | null },
  ];
}

function buildDueDatePresets(
  dayContext: DayContext,
): Array<{ key: string; labelKey: TranslationKey; value: string }> {
  return [
    { key: 'due-today', labelKey: 'contextMenu.dueToday', value: dayContext.todayYmd },
    { key: 'due-tomorrow', labelKey: 'contextMenu.dueTomorrow', value: dayContext.tomorrowYmd },
    { key: 'due-weekend', labelKey: 'contextMenu.dueWeekend', value: getNextWeekendYmd(dayContext.timezone) },
    { key: 'due-nextweek', labelKey: 'contextMenu.dueNextWeek', value: getNextMondayYmd(dayContext.timezone) },
  ];
}

// ─── Menu-item builders ─────────────────────────────────────────────────────

/** Build the "Defer" submenu items for an active task. */
export function buildDeferMenuItems(
  task: Task,
  dayContext: DayContext,
  t: TFn,
  helpers: ActionHelpers,
): ContextMenuItem {
  const presets = buildDeferPresets(dayContext);

  return {
    key: 'defer',
    label: t('task.defer'),
    icon: createElement(ClockIcon, { className: 'w-3.5 h-3.5' }),
    submenu: presets.map((preset) => ({
      key: preset.key,
      label: preset.date
        ? `${t(preset.labelKey)}  ${preset.date.slice(5)}`
        : t(preset.labelKey),
      onSelect: () => {
        const targetDate = preset.date;
        if (targetDate) {
          void runTaskDeferralWithUndo({
            task,
            runDefer: () => deferTaskUntil(task.id, targetDate, DEFER_REASON_NOT_TODAY),
            invalidate: () => helpers.invalidate(task.list_id),
            successMessage: t('task.deferred'),
            undoLabel: t('common.undo'),
            forwardErrorSource: 'contextMenu.defer',
            forwardErrorMessage: 'Failed to defer task',
            forwardErrorToastMessage: t('task.deferFailed'),
            undoErrorSource: 'contextMenu.undoDefer',
            undoErrorMessage: 'Failed to undo defer',
            undoErrorToastMessage: t('task.undoDeferFailed'),
          });
        } else {
          helpers.runUpdate(
            { status: 'someday' },
            'contextMenu.defer', 'Failed to move task to someday',
          );
        }
      },
    })),
  };
}

/** Build the "Due Date" submenu items for an active task. */
export function buildDueDateMenuItem(
  task: Task,
  dayContext: DayContext,
  t: TFn,
  runUpdate: RunUpdate,
): ContextMenuItem {
  const presets = buildDueDatePresets(dayContext);

  return {
    key: 'due-date',
    label: t('contextMenu.dueDate'),
    icon: createElement(CalendarDayIcon, { className: 'w-3.5 h-3.5' }),
    submenu: buildUpdateSubmenu({
      presets,
      fieldName: 'due_date',
      source: 'contextMenu.dueDate',
      errorMessage: 'Failed to set due date',
      successToast: t('task.updated'),
      dateSuffix: true,
      currentValue: task.due_date,
      clearItem: task.due_date ? {
        key: 'due-clear',
        labelKey: 'contextMenu.dueClear',
        errorMessage: 'Failed to clear due date',
        updates: buildDueDatePatch(task, null),
      } : undefined,
    }, t, runUpdate),
  };
}
