import type { Task } from '@/lib/ipc/tasks/models';
import type { TranslationKey } from '@/lib/i18n';
import { weekTimelineGeometry, WEEK_TIMELINE_DEFAULT_TASK_DURATION } from './weekTimelineLayout';

interface WeekTimelineTaskChipProps {
  task: Task;
  /** Localised "Wednesday 21 May" or similar — used in the a11y label. */
  dateLabel: string;
  t: (key: TranslationKey) => string;
  slotIndex?: number;
  slotCount?: number;
  onSelect?: () => void;
}

/**
 * Task with a `due_time` rendered as a slim chip on the week
 * timeline. Tasks without a due time end up in the all-day strip
 * (see WeekAllDayStrip) — they have no Y coordinate to anchor.
 *
 * Visually distinguished from event chips by an accent ring + the
 * checkmark glyph, so a column with both a meeting and a task at
 * 9:30 reads as two different concepts at a glance.
 */
export function WeekTimelineTaskChip({
  task,
  dateLabel,
  t,
  slotIndex = 0,
  slotCount = 1,
  onSelect,
}: WeekTimelineTaskChipProps) {
  const durationMinutes = task.estimated_minutes ?? WEEK_TIMELINE_DEFAULT_TASK_DURATION;
  const geometry = weekTimelineGeometry(task.due_time, null, durationMinutes);
  if (!geometry) return null;

  const widthPercent = 100 / slotCount;
  const leftPercent = widthPercent * slotIndex;
  const canFitTwoLines = geometry.height >= 36;

  return (
    <button
      type="button"
      onClick={onSelect}
      title={`${dateLabel} ${task.due_time ?? ''} — ${task.title}`}
      aria-label={`${t('common.task')}: ${dateLabel} ${task.due_time ?? ''} ${task.title}`}
      className="absolute overflow-hidden rounded-r-control border border-accent/30 bg-[var(--accent-tint-xs)] text-start text-text-primary hover:bg-[var(--accent-tint-sm)] active:scale-[0.99] transition-[background-color,transform] duration-100 focus-ring-soft"
      style={{
        top: geometry.top,
        height: geometry.height,
        left: `calc(${leftPercent}% + 2px)`,
        width: `calc(${widthPercent}% - 4px)`,
      }}
    >
      <div className="flex h-full flex-col gap-0.5 px-1.5 py-1">
        <div className="flex items-center gap-1 min-w-0">
          <span aria-hidden="true" className="shrink-0 text-accent text-2xs">✓</span>
          <span className="text-2xs truncate font-medium">{task.title}</span>
        </div>
        {canFitTwoLines && task.due_time && (
          <span className="text-2xs text-text-muted tabular-nums truncate">
            {task.due_time}
          </span>
        )}
      </div>
    </button>
  );
}
