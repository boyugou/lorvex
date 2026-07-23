import { eventColorStyles } from '@/lib/colorUtils';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import { eventTypeIcon } from '../eventTypeIcon';
import { weekTimelineGeometry, WEEK_TIMELINE_DEFAULT_EVENT_DURATION } from './weekTimelineLayout';

interface WeekTimelineEventChipProps {
  event: UnifiedCalendarEvent;
  /**
   * Absolute date this chip belongs to (`YYYY-MM-DD`). The chip is
   * rendered inside the day's column, so the date is implicit; pass
   * it through for the accessible label so screen readers announce
   * "Wednesday 21 May, 9:30 AM — Standup" instead of just the title.
   */
  dateLabel: string;
  /**
   * Localised fallback title for events whose `title` is empty.
   */
  untitledLabel: string;
  /**
   * Horizontal slot index (0 = leftmost) and total slot count when
   * overlapping events lay out side-by-side. Defaults to a full-width
   * single slot. The v1 layout is a flat-stack: every overlapping
   * event takes the same slot count, no nested splits.
   */
  slotIndex?: number;
  slotCount?: number;
  onSelect?: () => void;
}

/**
 * Single calendar event rendered as an absolutely-positioned chip
 * inside a `WeekDayColumn`. Geometry comes from `weekTimelineGeometry`;
 * the parent owns layout (`position: relative` on the column), so this
 * component only needs to position itself with `top` + `height` and an
 * inline-start offset when sharing the column with overlapping peers.
 */
export function WeekTimelineEventChip({
  event,
  dateLabel,
  untitledLabel,
  slotIndex = 0,
  slotCount = 1,
  onSelect,
}: WeekTimelineEventChipProps) {
  const geometry = weekTimelineGeometry(
    event.start_time,
    event.end_time,
    WEEK_TIMELINE_DEFAULT_EVENT_DURATION,
  );
  if (!geometry) return null;

  const widthPercent = 100 / slotCount;
  const leftPercent = widthPercent * slotIndex;

  const startMin = event.start_time ?? '';
  const endMin = event.end_time ?? '';
  const timeRange = endMin ? `${startMin}–${endMin}` : startMin;

  const colorStyles = eventColorStyles(event.color ?? null, 'soft');
  // `eventTypeIcon` returns a small emoji prefix string (or empty) —
  // birthdays / anniversaries / memorials get an inline glyph; regular
  // events render the title alone.
  const iconPrefix = eventTypeIcon(event.event_type);

  // Tight chip body: title row plus time row only when the chip is
  // tall enough. Anything shorter falls back to title-only rendering
  // so a 15-minute meeting does not truncate to a useless time stub.
  const canFitTwoLines = geometry.height >= 36;

  return (
    <button
      type="button"
      onClick={onSelect}
      title={`${dateLabel} ${timeRange} — ${event.title}`}
      aria-label={`${dateLabel} ${timeRange} ${event.title}`}
      className="absolute overflow-hidden rounded-r-control border-card text-start text-text-primary hover:brightness-95 active:scale-[0.99] transition-[filter,transform] duration-100 focus-ring-soft"
      style={{
        top: geometry.top,
        height: geometry.height,
        left: `calc(${leftPercent}% + 2px)`,
        width: `calc(${widthPercent}% - 4px)`,
        ...colorStyles,
      }}
    >
      <div className="flex h-full flex-col gap-0.5 px-1.5 py-1">
        <span className="text-2xs truncate font-medium" title={event.title}>
          {iconPrefix}{event.title || untitledLabel}
        </span>
        {canFitTwoLines && timeRange && (
          <span className="text-2xs text-text-muted tabular-nums truncate">
            {timeRange}
          </span>
        )}
      </div>
    </button>
  );
}
