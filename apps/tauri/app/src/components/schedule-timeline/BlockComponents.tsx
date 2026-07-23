import { useI18n } from '@/lib/i18n';
import type { ScheduleBlock } from '@/lib/ipc/tasks/models';
import { minutesBetween } from './blocks';

export function NowMarker({ time }: { time: string }) {
  return (
    <div className="flex items-center gap-3 py-0.5 px-3">
      <span className="text-accent text-xs font-mono w-11 shrink-0 text-end font-semibold">
        {time}
      </span>
      <div className="w-1.5 h-1.5 rounded-full bg-accent shrink-0" />
      <div className="flex-1 border-t border-accent/60" />
    </div>
  );
}

export function BufferBlock({ block }: { block: ScheduleBlock }) {
  const { t } = useI18n();
  const duration = minutesBetween(block.start_time, block.end_time);
  return (
    <div className="flex items-center gap-3 py-0.5 px-3">
      <span className="w-11 shrink-0" />
      <div className="w-0.5 h-3 bg-surface-3 rounded-full shrink-0" />
      <div className="flex-1 border-t border-dashed border-surface-3" />
      <span className="text-text-muted/50 text-xs shrink-0 tabular-nums">
        {duration}{t('common.min')}
      </span>
    </div>
  );
}

export function EventBlock({ block }: { block: ScheduleBlock }) {
  const { t } = useI18n();
  const duration = minutesBetween(block.start_time, block.end_time);
  return (
    <div className="flex items-start gap-3 py-2 px-3 rounded-r-card bg-[var(--warning-tint-xs)]">
      <span className="text-text-muted text-xs font-mono w-11 shrink-0 pt-0.5 text-end">
        {block.start_time}
      </span>
      <div className="w-4 shrink-0 flex items-center justify-center self-stretch">
        <div className="w-0.5 h-full rounded-full bg-[var(--warning-tint-xl)]" />
      </div>
      <div className="flex-1 min-w-0">
        <span className="text-sm text-text-secondary leading-snug">
          {block.title || t('schedule.untitledEvent')}
        </span>
      </div>
      <span className="text-text-muted/50 text-xs shrink-0 tabular-nums pt-0.5">
        {block.start_time}–{block.end_time} · {duration}{t('common.min')}
      </span>
    </div>
  );
}

export function ProgressBar({ completed, total }: { completed: number; total: number }) {
  const { t } = useI18n();
  const pct = total > 0 ? Math.round((completed / total) * 100) : 0;

  return (
    <div className="flex items-center gap-2.5 px-3 pb-2">
      <div className="flex-1 h-1.5 bg-surface-3 rounded-full overflow-hidden">
        <div
          className="progress-fill h-full bg-[var(--success-tint-xl)] rounded-full transition-transform duration-300"
          style={{ transform: `scaleX(${pct / 100})` }}
        />
      </div>
      <span className="text-text-muted text-xs tabular-nums shrink-0">
        {completed}/{total} {t('today.scheduleProgress')}
      </span>
    </div>
  );
}
