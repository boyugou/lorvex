import { useCallback, useEffect, useMemo, useRef } from 'react';

import { useConfiguredDayContext, getRelativeDateYmd } from '@/lib/dayContext';
import { getNextMondayYmd, getNextWeekendYmd } from '@/lib/dayContextMath';
import { useI18n, type TranslationKey } from '@/lib/i18n';
import type { Task } from '@/lib/ipc/tasks/models';
import { buildDueDatePatch } from '@/lib/tasks/dueAtPatch.logic';
import { CheckIcon } from './icons';
import { ModalShell } from './overlay';
import { isTaskPickerActivationKey } from './taskPickerKeyboard';
import { useCurrentPickerFocusIndex } from './useCurrentPickerFocusIndex';
import { useTaskPickerMutation } from './useTaskPickerMutation';

interface DueDatePickerOverlayProps {
  taskId: string;
  tasks: Task[];
  onClose: () => void;
}

interface DateOption {
  key: string;
  /// typed as `TranslationKey` so the call site can
  /// drop its `as Parameters<typeof t>[0]` cast and a typo here fails
  /// at compile time instead of falling through to the raw-key
  /// runtime fallback.
  labelKey: TranslationKey;
  getDate: (ctx: { timezone: string; todayYmd: string; tomorrowYmd: string }) => string | null;
}

/**
 * Keyboard-driven due date picker overlay triggered by the `t` shortcut.
 * Shows common date options; arrow keys navigate, Enter selects, Escape closes.
 */
export function DueDatePickerOverlay({ taskId, tasks, onClose }: DueDatePickerOverlayProps) {
  const { t } = useI18n();
  const listboxRef = useRef<HTMLDivElement>(null);
  const dayContext = useConfiguredDayContext();

  const task = tasks.find((tk) => tk.id === taskId);
  const { commitTaskPickerUpdate } = useTaskPickerMutation(task, onClose);

  const dateOptions = useMemo<DateOption[]>(() => [
    { key: 'today', labelKey: 'contextMenu.dueToday', getDate: (ctx) => ctx.todayYmd },
    { key: 'tomorrow', labelKey: 'contextMenu.dueTomorrow', getDate: (ctx) => ctx.tomorrowYmd },
    { key: 'weekend', labelKey: 'contextMenu.dueWeekend', getDate: (ctx) => getNextWeekendYmd(ctx.timezone) },
    { key: 'nextWeek', labelKey: 'contextMenu.dueNextWeek', getDate: (ctx) => getNextMondayYmd(ctx.timezone) },
    { key: 'twoWeeks', labelKey: 'datePicker.twoWeeks', getDate: (ctx) => getRelativeDateYmd(ctx.timezone, 14) },
    { key: 'nextMonth', labelKey: 'datePicker.nextMonth', getDate: (ctx) => getRelativeDateYmd(ctx.timezone, 30) },
    { key: 'none', labelKey: 'contextMenu.dueClear', getDate: () => null },
  ], []);

  // Determine which option matches the current due date
  const currentKey = useMemo(() => {
    if (!task?.due_date) return 'none';
    for (const opt of dateOptions) {
      const date = opt.getDate(dayContext);
      if (date === task.due_date) return opt.key;
    }
    return 'custom';
  }, [task?.due_date, dateOptions, dayContext]);
  const [focusIdx, setFocusIdx] = useCurrentPickerFocusIndex({
    currentKey,
    options: dateOptions,
  });

  useEffect(() => {
    if (!task) {
      onClose();
    }
  }, [task, onClose]);

  const setDueDate = useCallback(
    (option: DateOption) => {
      const newDate = option.getDate(dayContext);
      commitTaskPickerUpdate({
        patch: task ? buildDueDatePatch(task, newDate) : { due_date: newDate },
        successMessage: newDate ? t('contextMenu.dueDateSet') : t('contextMenu.dueDateCleared'),
        errorKey: 'datePicker.set',
        errorMessage: 'Failed to set due date',
      });
    },
    [commitTaskPickerUpdate, dayContext, t, task],
  );

  const handlePanelKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === 'ArrowDown' || e.key === 'j') {
        e.preventDefault();
        setFocusIdx((prev) => Math.min(prev + 1, dateOptions.length - 1));
      } else if (e.key === 'ArrowUp' || e.key === 'k') {
        e.preventDefault();
        setFocusIdx((prev) => Math.max(prev - 1, 0));
      } else if (isTaskPickerActivationKey(e.key)) {
        e.preventDefault();
        const option = dateOptions[focusIdx];
        if (option) setDueDate(option);
      }
    },
    [dateOptions, focusIdx, setDueDate, setFocusIdx],
  );

  if (!task) {
    return null;
  }

  return (
    <ModalShell
      open
      onClose={onClose}
      panelClassName="bg-surface-1 border border-popover rounded-r-panel shadow-[var(--shadow-popover)] w-[var(--popover-w-sm)] flex flex-col overflow-hidden"
      ariaLabel={t('datePicker.title')}
      onPanelKeyDown={handlePanelKeyDown}
      focusTarget={listboxRef}
    >
      <div className="px-3 pt-3 pb-1.5">
        <p className="text-text-muted text-xs font-medium">
          {t('datePicker.title')}
        </p>
        {task.due_date && (
          <p className="text-text-secondary text-xs mt-0.5">
            {t('datePicker.current')}: {task.due_date}
          </p>
        )}
      </div>

      {/* Listbox semantics — same rationale as
          RecurrencePickerOverlay. */}
      <div
        ref={listboxRef}
        className="px-1.5 pb-2"
        role="listbox"
        aria-orientation="vertical"
        tabIndex={0}
        aria-label={t('datePicker.title')}
        aria-activedescendant={
          dateOptions[focusIdx]
            ? `due-date-option-${dateOptions[focusIdx].key}`
            : undefined
        }
      >
        {dateOptions.map((option, idx) => {
          const dateValue = option.getDate(dayContext);
          return (
            <div
              key={option.key}
              id={`due-date-option-${option.key}`}
              role="option"
              aria-selected={option.key === currentKey}
              tabIndex={-1}
              onClick={() => setDueDate(option)}
              onKeyDown={(e) => {
                // Belt-and-braces: parent listbox handles keyboard
                // navigation via aria-activedescendant + onKeyDown, so
                // these options are normally activated by the parent.
                // The local Enter/Space handler keeps activation working
                // if focus ever lands on an option directly (a11y
                // baseline: any clickable element should also respond
                // to keyboard activation).
                if (isTaskPickerActivationKey(e.key)) {
                  e.preventDefault();
                  setDueDate(option);
                }
              }}
              className={`w-full text-start rounded-r-control px-2.5 py-1.5 text-sm flex items-center gap-2 transition-colors focus-ring-soft ${
                idx === focusIdx
                  ? 'bg-[var(--accent-tint-sm)] text-accent'
                  : 'text-text-primary hover:bg-surface-2/60'
              }`}
            >
              <span className="truncate">{t(option.labelKey)}</span>
              {dateValue && (
                <span className="ms-auto text-xs text-text-muted">{dateValue}</span>
              )}
              {option.key === currentKey && (
                <CheckIcon className={`${dateValue ? '' : 'ms-auto'} w-2.5 h-2.5 text-accent shrink-0`} aria-hidden="true" />
              )}
            </div>
          );
        })}
      </div>

    </ModalShell>
  );
}
