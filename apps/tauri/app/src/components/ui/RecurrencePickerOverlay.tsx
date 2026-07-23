import { useCallback, useEffect, useRef } from 'react';

import { useI18n, type TranslationKey } from '@/lib/i18n';
import type { Task } from '@/lib/ipc/tasks/models';
import {
  taskRecurrencePatchMatchesRaw,
  type TaskRecurrenceRulePatch,
} from '@/lib/taskRecurrence';
import { CheckIcon } from './icons';
import { ModalShell } from './overlay';
import { isTaskPickerActivationKey } from './taskPickerKeyboard';
import { useCurrentPickerFocusIndex } from './useCurrentPickerFocusIndex';
import { useTaskPickerMutation } from './useTaskPickerMutation';

interface RecurrencePickerOverlayProps {
  taskId: string;
  tasks: Task[];
  onClose: () => void;
}

/**
 * Structured recurrence rule patch — mirrors the typed
 * `RecurrenceRuleArgs` shape every write surface (Tauri `update_task`,
 * MCP `update_task` / `set_recurrence`) now accepts. `null` clears the
 * rule.
 *
 * The Tauri and MCP write surfaces share a single typed
 * recurrence-rule contract; this overlay hands the structured
 * object directly to the IPC rather than serialising and
 * hand-parsing on the other side.
 */
type RecurrenceRulePatch = TaskRecurrenceRulePatch;

interface RecurrenceOption {
  key: string;
  /// typed `TranslationKey` so the call site drops
  /// its `as Parameters<typeof t>[0]` cast.
  labelKey: TranslationKey;
  value: RecurrenceRulePatch;
}

const RECURRENCE_OPTIONS: RecurrenceOption[] = [
  { key: 'daily', labelKey: 'contextMenu.recurrenceDaily', value: { FREQ: 'DAILY', INTERVAL: 1 } },
  { key: 'weekdays', labelKey: 'recurrencePicker.weekdays', value: { FREQ: 'WEEKLY', INTERVAL: 1, BYDAY: ['MO', 'TU', 'WE', 'TH', 'FR'] } },
  { key: 'weekly', labelKey: 'contextMenu.recurrenceWeekly', value: { FREQ: 'WEEKLY', INTERVAL: 1 } },
  { key: 'biweekly', labelKey: 'recurrencePicker.biweekly', value: { FREQ: 'WEEKLY', INTERVAL: 2 } },
  { key: 'monthly', labelKey: 'contextMenu.recurrenceMonthly', value: { FREQ: 'MONTHLY', INTERVAL: 1 } },
  { key: 'yearly', labelKey: 'contextMenu.recurrenceYearly', value: { FREQ: 'YEARLY', INTERVAL: 1 } },
  { key: 'none', labelKey: 'recurrencePicker.none', value: null },
];

/**
 * Keyboard-driven recurrence picker overlay triggered by the `R` shortcut.
 * Shows common recurrence options; arrow keys navigate, Enter selects, Escape closes.
 */
export function RecurrencePickerOverlay({ taskId, tasks, onClose }: RecurrencePickerOverlayProps) {
  const { t } = useI18n();
  const listboxRef = useRef<HTMLDivElement>(null);

  const task = tasks.find((tk) => tk.id === taskId);
  const { commitTaskPickerUpdate } = useTaskPickerMutation(task, onClose);

  // `currentKey` is a derived primitive computed
  // from a 7-entry array lookup; `useMemo` here costs more than the
  // recompute (memo bookkeeping + dep array) and the value is only
  // read once per render against `option.key` in the option list.
  // Inline.
  //
  // `task.recurrence` is the stored
  // canonical RRULE JSON (a string from the DB) whose key order the
  // canonical normalizer pins to alphabetical (`BYDAY,FREQ,INTERVAL`).
  // `option.value` is the structured object we now send to the IPC,
  // whose key order follows insertion. Compare structurally — parse
  // both sides and let the shared recurrence helper walk the keys —
  // rather than naively `JSON.stringify`-ing one side and tripping
  // on the BYDAY-first canonical ordering.
  const currentKey: string = !task?.recurrence
    ? 'none'
    : (() => {
        return (
          RECURRENCE_OPTIONS.find(
            (o) => o.value !== null && taskRecurrencePatchMatchesRaw(o.value, task.recurrence),
          )?.key ?? 'custom'
        );
      })();
  const [focusIdx, setFocusIdx] = useCurrentPickerFocusIndex({
    currentKey,
    options: RECURRENCE_OPTIONS,
  });

  useEffect(() => {
    if (!task) {
      onClose();
    }
  }, [task, onClose]);

  const setRecurrence = useCallback(
    (option: RecurrenceOption) => {
      const isClearing = option.value === null;
      commitTaskPickerUpdate({
        patch: { recurrence: option.value },
        successMessage: isClearing ? t('contextMenu.recurrenceCleared') : t('contextMenu.recurrenceSet'),
        errorKey: 'recurrencePicker.set',
        errorMessage: 'Failed to set recurrence',
      });
    },
    [commitTaskPickerUpdate, t],
  );

  const handlePanelKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === 'ArrowDown' || e.key === 'j') {
        e.preventDefault();
        setFocusIdx((prev) => Math.min(prev + 1, RECURRENCE_OPTIONS.length - 1));
      } else if (e.key === 'ArrowUp' || e.key === 'k') {
        e.preventDefault();
        setFocusIdx((prev) => Math.max(prev - 1, 0));
      } else if (isTaskPickerActivationKey(e.key)) {
        e.preventDefault();
        const option = RECURRENCE_OPTIONS[focusIdx];
        if (option) setRecurrence(option);
      }
    },
    [focusIdx, setRecurrence, setFocusIdx],
  );

  if (!task) {
    return null;
  }

  return (
    <ModalShell
      open
      onClose={onClose}
      panelClassName="bg-surface-1 border border-popover rounded-r-panel shadow-[var(--shadow-popover)] w-[var(--popover-w-sm)] flex flex-col overflow-hidden"
      ariaLabel={t('recurrencePicker.title')}
      onPanelKeyDown={handlePanelKeyDown}
      focusTarget={listboxRef}
    >
      <div className="px-3 pt-3 pb-1.5">
        <p className="text-text-muted text-xs font-medium">
          {t('recurrencePicker.title')}
        </p>
      </div>

      {/* Expose listbox semantics so AT announces
          "list of N items" + "option, selected" instead of a flat
          stack of unrelated buttons. The arrow-key roving is tracked
          on the panel via `handlePanelKeyDown`, so `aria-activedescendant`
          on the listbox container points at the focused option. */}
      <div
        ref={listboxRef}
        className="px-1.5 pb-2"
        role="listbox"
        aria-orientation="vertical"
        tabIndex={0}
        aria-label={t('recurrencePicker.title')}
        aria-activedescendant={
          RECURRENCE_OPTIONS[focusIdx]
            ? `recurrence-option-${RECURRENCE_OPTIONS[focusIdx].key}`
            : undefined
        }
      >
        {RECURRENCE_OPTIONS.map((option, idx) => (
          <div
            key={option.key}
            id={`recurrence-option-${option.key}`}
            role="option"
            aria-selected={option.key === currentKey}
            tabIndex={-1}
            onClick={() => setRecurrence(option)}
            onKeyDown={(e) => {
              // Parent listbox owns navigation via aria-activedescendant;
              // local Enter/Space keeps activation working if focus ever
              // lands directly on an option (a11y baseline).
              if (isTaskPickerActivationKey(e.key)) {
                e.preventDefault();
                setRecurrence(option);
              }
            }}
            className={`w-full text-start rounded-r-control px-2.5 py-1.5 text-sm flex items-center gap-2 transition-colors focus-ring-soft ${
              idx === focusIdx
                ? 'bg-[var(--accent-tint-sm)] text-accent'
                : 'text-text-primary hover:bg-surface-2/60'
            }`}
          >
            <span className="truncate">{t(option.labelKey)}</span>
            {option.key === currentKey && (
              <CheckIcon className="ms-auto w-2.5 h-2.5 text-accent shrink-0" aria-hidden="true" />
            )}
          </div>
        ))}
      </div>

    </ModalShell>
  );
}
