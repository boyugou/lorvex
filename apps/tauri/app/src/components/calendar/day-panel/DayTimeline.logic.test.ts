import { describe, expect, it } from 'vitest';
import {
  DAY_TIMELINE_ROW_HEIGHT,
  dayTimelineLaneStyle,
  dayTimelineResizedMinutes,
  resolveDayTimelineInitialScrollTop,
  resolveDayTimelineKeyboardReschedule,
  DAY_TIMELINE_TASK_KEYSHORTCUTS,
} from './DayTimeline.logic';

describe('resolveDayTimelineInitialScrollTop', () => {
  it('opens early travel days at midnight so pre-dawn context stays reachable', () => {
    expect(resolveDayTimelineInitialScrollTop({
      nowHHMM: '13:00',
      viewportHeight: 600,
      timedItems: [
        { startTime: '09:05' },
        { startTime: '04:22' },
        { startTime: '06:22' },
      ],
    })).toBe(0);
  });

  it('anchors ordinary days just above the earliest timed item', () => {
    expect(resolveDayTimelineInitialScrollTop({
      nowHHMM: '13:00',
      viewportHeight: 600,
      timedItems: [
        { startTime: '09:05' },
        { startTime: '11:00' },
      ],
    })).toBeCloseTo(((9 * 60 + 5 - 30) / 60) * DAY_TIMELINE_ROW_HEIGHT);
  });

  it('treats 08:00 as the ordinary-day scroll boundary', () => {
    expect(resolveDayTimelineInitialScrollTop({
      nowHHMM: '13:00',
      viewportHeight: 600,
      timedItems: [{ startTime: '07:59' }],
    })).toBe(0);

    expect(resolveDayTimelineInitialScrollTop({
      nowHHMM: '13:00',
      viewportHeight: 600,
      timedItems: [{ startTime: '08:00' }],
    })).toBeCloseTo(7.5 * DAY_TIMELINE_ROW_HEIGHT);
  });

  it('falls back to current time when the day has no timed items', () => {
    expect(resolveDayTimelineInitialScrollTop({
      nowHHMM: '13:00',
      viewportHeight: 600,
      timedItems: [],
    })).toBeCloseTo(13 * DAY_TIMELINE_ROW_HEIGHT - 200);
  });

  it('lands at the top when neither timed content nor current time is available', () => {
    expect(resolveDayTimelineInitialScrollTop({
      nowHHMM: null,
      viewportHeight: 600,
      timedItems: [{ startTime: null }, { startTime: 'bad-time' }],
    })).toBe(0);
  });
});

describe('resolveDayTimelineKeyboardReschedule', () => {
  it('moves timed tasks by one snap with Mod+Shift+ArrowUp/Down', () => {
    expect(resolveDayTimelineKeyboardReschedule({
      key: 'ArrowUp',
      shiftKey: true,
      metaKey: true,
      oldTime: '09:30',
    })).toBe('09:15');

    expect(resolveDayTimelineKeyboardReschedule({
      key: 'ArrowDown',
      shiftKey: true,
      ctrlKey: true,
      oldTime: '09:30',
    })).toBe('09:45');
  });

  it('ignores navigation keys without the complete reschedule chord', () => {
    expect(resolveDayTimelineKeyboardReschedule({
      key: 'ArrowDown',
      shiftKey: true,
      oldTime: '09:30',
    })).toBeNull();
    expect(resolveDayTimelineKeyboardReschedule({
      key: 'ArrowDown',
      shiftKey: true,
      metaKey: true,
      altKey: true,
      oldTime: '09:30',
    })).toBeNull();
    expect(resolveDayTimelineKeyboardReschedule({
      key: 'Enter',
      shiftKey: true,
      metaKey: true,
      oldTime: '09:30',
    })).toBeNull();
  });

  it('clamps timed movement to the visible timeline range', () => {
    expect(resolveDayTimelineKeyboardReschedule({
      key: 'ArrowUp',
      shiftKey: true,
      metaKey: true,
      oldTime: '00:00',
    })).toBeNull();
    expect(resolveDayTimelineKeyboardReschedule({
      key: 'ArrowDown',
      shiftKey: true,
      metaKey: true,
      oldTime: '23:45',
    })).toBeNull();
  });

  it('lets untimed tasks enter the timeline from either edge', () => {
    expect(resolveDayTimelineKeyboardReschedule({
      key: 'ArrowDown',
      shiftKey: true,
      metaKey: true,
      oldTime: null,
    })).toBe('00:00');
    expect(resolveDayTimelineKeyboardReschedule({
      key: 'ArrowUp',
      shiftKey: true,
      ctrlKey: true,
      oldTime: null,
    })).toBe('23:45');
  });
});

describe('DAY_TIMELINE_TASK_KEYSHORTCUTS', () => {
  it('advertises both macOS and control-key modifier forms', () => {
    expect(DAY_TIMELINE_TASK_KEYSHORTCUTS).toContain('Meta+Shift+ArrowUp');
    expect(DAY_TIMELINE_TASK_KEYSHORTCUTS).toContain('Control+Shift+ArrowDown');
  });
});

describe('dayTimelineResizedMinutes', () => {
  // 60px row height = 1px per minute, so a +30px drag adds 30 minutes.
  const base = { rowHeight: 60, snapMinutes: 15, minMinutes: 15 };

  it('grows the duration as the bottom edge is dragged down, snapped', () => {
    expect(dayTimelineResizedMinutes({ startMinutes: 30, deltaY: 30, ...base })).toBe(60);
    // 22px → 30 → 52min → snaps to 45 (nearest 15).
    expect(dayTimelineResizedMinutes({ startMinutes: 30, deltaY: 22, ...base })).toBe(45);
  });

  it('shrinks when dragged up but never below the minimum', () => {
    expect(dayTimelineResizedMinutes({ startMinutes: 60, deltaY: -30, ...base })).toBe(30);
    expect(dayTimelineResizedMinutes({ startMinutes: 30, deltaY: -100, ...base })).toBe(15);
  });
});

describe('dayTimelineLaneStyle', () => {
  it('spans the full band for a lone chip (no slot)', () => {
    expect(dayTimelineLaneStyle(undefined)).toEqual({
      insetInlineStart: 'calc(2.5rem + (100% - 2.75rem) * 0 / 1)',
      width: 'calc((100% - 2.75rem) / 1 - 0px)',
    });
  });

  it('spans the full band, no gap, when count is 1', () => {
    expect(dayTimelineLaneStyle({ index: 0, count: 1 })).toEqual({
      insetInlineStart: 'calc(2.5rem + (100% - 2.75rem) * 0 / 1)',
      width: 'calc((100% - 2.75rem) / 1 - 0px)',
    });
  });

  it('splits overlapping chips into equal side-by-side columns with a gap', () => {
    expect(dayTimelineLaneStyle({ index: 0, count: 3 })).toEqual({
      insetInlineStart: 'calc(2.5rem + (100% - 2.75rem) * 0 / 3)',
      width: 'calc((100% - 2.75rem) / 3 - 2px)',
    });
    expect(dayTimelineLaneStyle({ index: 2, count: 3 })).toEqual({
      insetInlineStart: 'calc(2.5rem + (100% - 2.75rem) * 2 / 3)',
      width: 'calc((100% - 2.75rem) / 3 - 2px)',
    });
  });

  it('treats a degenerate zero count as a single full-width column', () => {
    expect(dayTimelineLaneStyle({ index: 0, count: 0 })).toEqual({
      insetInlineStart: 'calc(2.5rem + (100% - 2.75rem) * 0 / 1)',
      width: 'calc((100% - 2.75rem) / 1 - 0px)',
    });
  });
});
