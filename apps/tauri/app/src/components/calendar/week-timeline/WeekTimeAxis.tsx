import { useMemo } from 'react';

import {
  WEEK_TIMELINE_HOUR_COUNT,
  WEEK_TIMELINE_HOUR_START,
  WEEK_TIMELINE_ROW_HEIGHT,
  WEEK_TIMELINE_TIME_AXIS_WIDTH,
} from './weekTimelineLayout';

/**
 * Left-edge column rendering the hour labels (00:00, 01:00, …).
 *
 * Sticky on the inline-start axis so a horizontal-scroll viewport (the
 * future "many-day" zoom levels) keeps the labels in view. Each label
 * sits at the row's *top* edge with a slight negative offset so the
 * label baseline aligns with the gridline rather than floating below it
 * for quick visual alignment.
 *
 * `aria-hidden` because every chip carries its own time in its
 * accessible label; surfacing the static axis labels to a screen
 * reader would clutter the tree without adding information.
 */
export function WeekTimeAxis() {
  const hours = useMemo(
    () =>
      Array.from({ length: WEEK_TIMELINE_HOUR_COUNT }, (_, index) => {
        const hour = WEEK_TIMELINE_HOUR_START + index;
        return `${String(hour).padStart(2, '0')}:00`;
      }),
    [],
  );

  return (
    <div
      aria-hidden="true"
      className="shrink-0 relative border-e border-surface-3 bg-surface-1/40"
      style={{ width: WEEK_TIMELINE_TIME_AXIS_WIDTH }}
    >
      {hours.map((label, index) => (
        <div
          key={label}
          className="absolute inset-x-0 flex justify-end pe-2 text-2xs text-text-muted tabular-nums"
          style={{
            top: index * WEEK_TIMELINE_ROW_HEIGHT,
            // Offset by -6px so the label centers above the gridline
            // rather than starting after it.
            transform: 'translateY(-6px)',
          }}
        >
          {label}
        </div>
      ))}
    </div>
  );
}
