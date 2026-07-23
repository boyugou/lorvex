import { createElement } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import { updateTask } from '@/lib/ipc/tasks/mutations/quickCapture';
import { ArrowRightIcon, RecurrenceIcon, TimerIcon } from '../ui/icons';
import type { ContextMenuItem } from '../context-menu/ContextMenu';
import type { TranslationKey } from '@/lib/i18n';
import { buildUpdateSubmenu } from './buildUpdateSubmenu';
import type { ActionHelpers, RunUpdate } from './types';

type TFn = (key: TranslationKey) => string;

type RecurrenceRulePatch = {
  FREQ: 'DAILY' | 'WEEKLY' | 'MONTHLY' | 'YEARLY';
  INTERVAL: number;
};

// ─── Recurrence ──────────────────────────────────────────────────────────────

/** Build the "Recurrence" submenu item. */
export function buildRecurrenceMenuItem(
  task: Task,
  t: TFn,
  runUpdate: RunUpdate,
): ContextMenuItem {
  const recurrencePresets: Array<{ key: string; labelKey: TranslationKey; value: RecurrenceRulePatch }> = [
    { key: 'recur-daily', labelKey: 'contextMenu.recurrenceDaily', value: { FREQ: 'DAILY', INTERVAL: 1 } },
    { key: 'recur-weekly', labelKey: 'contextMenu.recurrenceWeekly', value: { FREQ: 'WEEKLY', INTERVAL: 1 } },
    { key: 'recur-monthly', labelKey: 'contextMenu.recurrenceMonthly', value: { FREQ: 'MONTHLY', INTERVAL: 1 } },
    { key: 'recur-yearly', labelKey: 'contextMenu.recurrenceYearly', value: { FREQ: 'YEARLY', INTERVAL: 1 } },
  ];

  return {
    key: 'recurrence',
    label: t('contextMenu.recurrence'),
    icon: createElement(RecurrenceIcon, { className: 'w-3.5 h-3.5' }),
    submenu: buildUpdateSubmenu({
      presets: recurrencePresets,
      fieldName: 'recurrence',
      source: 'contextMenu.recurrence',
      errorMessage: 'Failed to set recurrence',
      successToast: t('contextMenu.recurrenceSet'),
      clearItem: task.recurrence ? {
        key: 'recur-clear',
        labelKey: 'contextMenu.recurrenceClear',
        successToast: t('contextMenu.recurrenceCleared'),
        errorMessage: 'Failed to clear recurrence',
      } : undefined,
    }, t, runUpdate),
  };
}

// ─── Duration ────────────────────────────────────────────────────────────────

/** Build the "Duration" submenu item. */
export function buildDurationMenuItem(
  task: Task,
  t: TFn,
  runUpdate: RunUpdate,
): ContextMenuItem {
  const durationPresets: Array<{ key: string; labelKey: TranslationKey; value: number }> = [
    { key: 'dur-15', labelKey: 'contextMenu.duration15m', value: 15 },
    { key: 'dur-30', labelKey: 'contextMenu.duration30m', value: 30 },
    { key: 'dur-60', labelKey: 'contextMenu.duration1h', value: 60 },
    { key: 'dur-120', labelKey: 'contextMenu.duration2h', value: 120 },
    { key: 'dur-240', labelKey: 'contextMenu.duration4h', value: 240 },
  ];

  return {
    key: 'duration',
    label: t('contextMenu.duration'),
    icon: createElement(TimerIcon, { className: 'w-3.5 h-3.5' }),
    submenu: buildUpdateSubmenu({
      presets: durationPresets,
      fieldName: 'estimated_minutes',
      source: 'contextMenu.duration',
      errorMessage: 'Failed to set duration',
      successToast: t('contextMenu.durationSet'),
      currentValue: task.estimated_minutes,
      clearItem: task.estimated_minutes ? {
        key: 'dur-clear',
        labelKey: 'contextMenu.durationClear',
        successToast: t('contextMenu.durationCleared'),
        errorMessage: 'Failed to clear duration',
      } : undefined,
    }, t, runUpdate),
  };
}

// ─── Move to list ────────────────────────────────────────────────────────────

interface ListInfo {
  id: string;
  name: string;
}

/** Build the "Move to list" submenu item, or null if no other lists exist. */
export function buildMoveToListMenuItem(
  task: Task,
  lists: ListInfo[],
  t: TFn,
  helpers: Pick<ActionHelpers, 'runAction'>,
): ContextMenuItem | null {
  const otherLists = lists.filter((l) => l.id !== task.list_id);
  if (otherLists.length === 0) return null;

  return {
    key: 'move',
    label: t('contextMenu.moveToList'),
    icon: createElement(ArrowRightIcon, { className: 'w-3.5 h-3.5' }),
    submenu: otherLists.map((list) => ({
      key: `move-${list.id}`,
      label: list.name,
      onSelect: () => helpers.runAction(
        updateTask(task.id, { list_id: list.id }),
        'contextMenu.move', 'Failed to move task',
        `${t('contextMenu.movedToList')} ${list.name}`,
        [list.id],
      ),
    })),
  };
}
