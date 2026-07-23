import { useRef } from 'react';
import { XIcon } from '@/components/ui/icons';
import { Tooltip } from '@/components/ui/Tooltip';
import {
  getOptionalTimeInputValue,
  resolveOptionalTimeInputBlurValue,
} from '@/components/task-detail/taskMetadataTemporalInput';
import { buildDueTimePatch } from '@/lib/tasks/dueAtPatch.logic';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { isImeComposing } from '@/lib/ime';
import { InlineEditField } from '../primitives';
import type { TaskTemporalFieldsProps } from './types';

/**
 * Inline HH:mm time editor for the secondary metadata grid. Commits
 * on Enter or blur (Enter is the muscle-memory save key, blur covers
 * mouse users picking via the OS time chrome). The clear button has
 * `onMouseDown.preventDefault` + a `relatedTarget` guard so blur fires
 * cleanly when the user clicks the X.
 *
 * `wrapClearInTooltip` controls whether the clear button is wrapped in
 * a Tooltip — the bare time slot (no surrounding label cell) skips the
 * tooltip so the clear hit-target stays within the row baseline.
 */
export function DueTimeField({
  task,
  t,
  onSave,
  wrapClearInTooltip = false,
}: {
  task: TaskTemporalFieldsProps['task'];
  t: TaskTemporalFieldsProps['t'];
  onSave: TaskTemporalFieldsProps['onSave'];
  wrapClearInTooltip?: boolean;
}) {
  const dayContext = useConfiguredDayContext();
  const clearButtonRef = useRef<HTMLButtonElement>(null);
  const saveDueTime = async (value: string | null) => {
    await onSave(buildDueTimePatch(task, value, dayContext.todayYmd));
  };

  return (
    <InlineEditField
      label={t('task.time')}
      display={task.due_time || <span className="text-text-muted/50 italic text-xs">{t('task.noTime')}</span>}
    >
      {(close) => {
        const clearButton = (
          <button
            ref={clearButtonRef}
            type="button"
            onMouseDown={(event) => { event.preventDefault(); }}
            onClick={async () => { await saveDueTime(null); close(); }}
            aria-label={t('quickdate.clear')}
            className="text-text-muted hover:text-danger text-xs shrink-0 rounded-r-control focus-ring-soft"
          >
            <XIcon className="w-3 h-3" />
          </button>
        );
        return (
          <div className="flex gap-1 items-center">
            <input
              type="time"
              aria-label={t('task.time')}
              defaultValue={getOptionalTimeInputValue(task.due_time)}
              autoFocus
              className="bg-surface-2 border border-surface-3 rounded-r-control px-2.5 py-1.5 text-xs text-text-primary w-full focus-ring-soft outline-hidden transition-colors hover:border-accent/30 [color-scheme:dark]"
              onKeyDown={async (event) => {
                if (isImeComposing(event)) return;
                if (event.key === 'Escape') { close(); return; }
                // D3: Enter commits the typed/picked time and
                // closes the editor.
                if (event.key === 'Enter') {
                  event.preventDefault();
                  const value = resolveOptionalTimeInputBlurValue(task.due_time, event.currentTarget.value);
                  if (value !== undefined) await saveDueTime(value);
                  close();
                }
              }}
              onBlur={async (event) => {
                if (event.relatedTarget === clearButtonRef.current) return;
                const value = resolveOptionalTimeInputBlurValue(task.due_time, event.target.value);
                if (value !== undefined) await saveDueTime(value);
                close();
              }}
            />
            {task.due_time && (
              wrapClearInTooltip ? (
                <Tooltip label={t('quickdate.clear')}>
                  {clearButton}
                </Tooltip>
              ) : (
                clearButton
              )
            )}
          </div>
        );
      }}
    </InlineEditField>
  );
}
