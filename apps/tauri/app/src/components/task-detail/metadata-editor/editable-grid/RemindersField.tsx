import { useRef, useState } from 'react';
import { XIcon } from '@/components/ui/icons';
import { RevealButton } from '@/components/ui/RevealButton';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { isImeComposing } from '@/lib/ime';
import { formatTimestamp } from '@/lib/dates/dateLocale';
import type { TaskReminder } from '@/lib/ipc/tasks/models';
import { useTaskReminderActions } from './useTaskReminderActions';
import type { TaskTemporalFieldsProps } from './types';

/**
 * Per-task reminders list + inline "add reminder" datetime picker.
 * Owned by the secondary metadata grid (spans both columns). Composing
 * the list/add UI as a single component keeps the in-flight guard
 * (`runGuardedReminderSubmit`) and the local `adding` state colocated.
 */
export function RemindersField({
  taskId,
  locale,
  t,
}: {
  taskId: string;
  locale: string;
  t: TaskTemporalFieldsProps['t'];
}) {
  const [adding, setAdding] = useState(false);
  const addReminderInFlightRef = useRef(false);
  const { timezone } = useConfiguredDayContext();
  const {
    pendingReminders,
    handleAddReminder,
    handleRemoveReminder,
  } = useTaskReminderActions({ taskId, timezone });
  const now = new Date();

  const formatReminder = (r: TaskReminder) => {
    const d = new Date(r.reminder_at);
    const expired = d < now;
    // `formatTimestamp` routes through the shared memoized formatter
    // cache so the reminders list reuses one `Intl.DateTimeFormat` per
    // (locale, options-shape, timezone) tuple across all rows.
    const text = formatTimestamp(r.reminder_at, locale, timezone, {
      month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit',
    });
    return { text, expired };
  };

  const submitReminder = async (value: string): Promise<boolean> => {
    return runGuardedReminderSubmit(addReminderInFlightRef, value, handleAddReminder);
  };

  return (
    <div className="col-span-2">
      <div className="flex items-center justify-between mb-1">
        <span className="text-text-muted text-xs font-medium">{t('task.reminder')}</span>
        <button
          type="button"
          onClick={() => setAdding(true)}
          className="text-accent text-xs hover:text-accent/80 focus-ring-soft rounded-r-control px-1"
        >
          + {t('task.addReminder')}
        </button>
      </div>
      {pendingReminders.length === 0 && !adding && (
        <p className="text-text-muted/50 italic text-xs">{t('task.noReminder')}</p>
      )}
      {pendingReminders.map(r => {
        const { text, expired } = formatReminder(r);
        return (
          <div key={r.id} className="flex items-center gap-1.5 py-0.5 group">
            <span className={`text-xs ${expired ? 'text-text-muted line-through' : 'text-text-secondary'}`}>
              {text}
            </span>
            <RevealButton
              onClick={() => { void handleRemoveReminder(r.id); }}
              className="text-xs shrink-0"
              aria-label={`${t('quickdate.clear')}: ${text}`}
            >
              <XIcon className="w-3 h-3" />
            </RevealButton>
          </div>
        );
      })}
      {adding && (
        <div className="flex gap-1 items-center mt-1">
          <input
            type="datetime-local"
            aria-label={t('task.addReminder')}
            autoFocus
            className="bg-surface-2 border border-surface-3 rounded-r-control px-2.5 py-1.5 text-xs text-text-primary flex-1 focus-ring-soft outline-hidden transition-colors hover:border-accent/30 [color-scheme:dark]"
            onKeyDown={(event) => {
              if (isImeComposing(event)) return;
              if (event.key === 'Escape') setAdding(false);
              if (event.key === 'Enter') {
                void submitReminder((event.target as HTMLInputElement).value).then((added) => {
                  if (added) {
                    setAdding(false);
                  }
                });
              }
            }}
            onBlur={(event) => {
              if (event.target.value) {
                void submitReminder(event.target.value).then((added) => {
                  if (added) {
                    setAdding(false);
                  }
                });
                return;
              }
              setAdding(false);
            }}
          />
        </div>
      )}
    </div>
  );
}

export async function runGuardedReminderSubmit(
  inFlightRef: { current: boolean },
  value: string,
  submit: (value: string) => Promise<boolean>,
): Promise<boolean> {
  if (!value || inFlightRef.current) return false;
  inFlightRef.current = true;
  try {
    return await submit(value);
  } finally {
    inFlightRef.current = false;
  }
}
