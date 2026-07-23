import { useCallback, useEffect, useMemo, useRef } from 'react';

import { useI18n, type TranslationKey } from '@/lib/i18n';
import type { Task } from '@/lib/ipc/tasks/models';
import { CheckIcon } from './icons';
import { ModalShell } from './overlay';
import { isTaskPickerActivationKey } from './taskPickerKeyboard';
import { useCurrentPickerFocusIndex } from './useCurrentPickerFocusIndex';
import { useTaskPickerMutation } from './useTaskPickerMutation';

interface DurationPickerOverlayProps {
  taskId: string;
  tasks: Task[];
  onClose: () => void;
}

interface DurationOption {
  key: string;
  /// typed `TranslationKey` so the call site drops
  /// its `as Parameters<typeof t>[0]` cast and a typo at the
  /// definition fails compile-time.
  labelKey: TranslationKey;
  minutes: number | null;
}

const DURATION_OPTIONS: DurationOption[] = [
  { key: '15m', labelKey: 'contextMenu.duration15m', minutes: 15 },
  { key: '30m', labelKey: 'contextMenu.duration30m', minutes: 30 },
  { key: '1h', labelKey: 'contextMenu.duration1h', minutes: 60 },
  { key: '2h', labelKey: 'contextMenu.duration2h', minutes: 120 },
  { key: '4h', labelKey: 'contextMenu.duration4h', minutes: 240 },
  { key: 'none', labelKey: 'contextMenu.durationClear', minutes: null },
];

/**
 * Keyboard-driven duration picker overlay triggered by the `w` shortcut.
 * Shows common duration options; arrow keys navigate, Enter selects, Escape closes.
 */
export function DurationPickerOverlay({ taskId, tasks, onClose }: DurationPickerOverlayProps) {
  const { t } = useI18n();
  const listboxRef = useRef<HTMLDivElement>(null);

  const task = tasks.find((tk) => tk.id === taskId);
  const { commitTaskPickerUpdate } = useTaskPickerMutation(task, onClose);

  const currentKey = useMemo(() => {
    if (!task?.estimated_minutes) return 'none';
    return DURATION_OPTIONS.find((o) => o.minutes === task.estimated_minutes)?.key ?? 'custom';
  }, [task?.estimated_minutes]);
  const [focusIdx, setFocusIdx] = useCurrentPickerFocusIndex({
    currentKey,
    options: DURATION_OPTIONS,
  });

  useEffect(() => {
    if (!task) {
      onClose();
    }
  }, [task, onClose]);

  const setDuration = useCallback(
    (option: DurationOption) => {
      const isClearing = option.minutes === null;
      commitTaskPickerUpdate({
        patch: { estimated_minutes: option.minutes },
        successMessage: isClearing ? t('contextMenu.durationCleared') : t('contextMenu.durationSet'),
        errorKey: 'durationPicker.set',
        errorMessage: 'Failed to set duration',
      });
    },
    [commitTaskPickerUpdate, t],
  );

  const handlePanelKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === 'ArrowDown' || e.key === 'j') {
        e.preventDefault();
        setFocusIdx((prev) => Math.min(prev + 1, DURATION_OPTIONS.length - 1));
      } else if (e.key === 'ArrowUp' || e.key === 'k') {
        e.preventDefault();
        setFocusIdx((prev) => Math.max(prev - 1, 0));
      } else if (isTaskPickerActivationKey(e.key)) {
        e.preventDefault();
        const option = DURATION_OPTIONS[focusIdx];
        if (option) setDuration(option);
      }
    },
    [focusIdx, setDuration, setFocusIdx],
  );

  if (!task) {
    return null;
  }

  return (
    <ModalShell
      open
      onClose={onClose}
      panelClassName="bg-surface-1 border border-popover rounded-r-panel shadow-[var(--shadow-popover)] w-[var(--popover-w-sm)] flex flex-col overflow-hidden"
      ariaLabel={t('durationPicker.title')}
      onPanelKeyDown={handlePanelKeyDown}
      focusTarget={listboxRef}
    >
      <div className="px-3 pt-3 pb-1.5">
        <p className="text-text-muted text-xs font-medium">
          {t('durationPicker.title')}
        </p>
        {task.estimated_minutes != null && task.estimated_minutes > 0 && (
          // Guard against negative / non-finite values from a
          // malformed import or adversarial sync envelope. The `> 0`
          // gate treats non-positive as "no estimate shown" — the
          // same visual affordance a missing estimate produces — so
          // a stray `-75` never renders verbatim.
          <p className="text-text-secondary text-xs mt-0.5">
            {t('datePicker.current')}: {task.estimated_minutes >= 60
              ? `${Math.floor(task.estimated_minutes / 60)}${t('common.hourShort')}${task.estimated_minutes % 60 > 0 ? ` ${task.estimated_minutes % 60}${t('common.min')}` : ''}`
              : `${task.estimated_minutes}${t('common.min')}`}
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
        aria-label={t('durationPicker.title')}
        aria-activedescendant={
          DURATION_OPTIONS[focusIdx]
            ? `duration-option-${DURATION_OPTIONS[focusIdx].key}`
            : undefined
        }
      >
        {DURATION_OPTIONS.map((option, idx) => (
          <div
            key={option.key}
            id={`duration-option-${option.key}`}
            role="option"
            aria-selected={option.key === currentKey}
            tabIndex={-1}
            onClick={() => setDuration(option)}
            onKeyDown={(e) => {
              // Parent listbox owns navigation via aria-activedescendant;
              // local Enter/Space keeps activation working if focus ever
              // lands directly on an option (a11y baseline).
              if (isTaskPickerActivationKey(e.key)) {
                e.preventDefault();
                setDuration(option);
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
