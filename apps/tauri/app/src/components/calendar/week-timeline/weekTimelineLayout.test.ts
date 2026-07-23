import { describe, expect, it } from 'vitest';

import { DAY_TIMELINE_ROW_HEIGHT } from '../day-panel/DayTimeline.logic';
import {
  computeWeekTimelineSlots,
  weekTimelineGeometry,
  weekTimelineInitialScrollTop,
  weekTimelineMinutesToTop,
  weekTimelineScrollAnchorItems,
  WEEK_TIMELINE_DAY_MIN_WIDTH,
  WEEK_TIMELINE_HOUR_COUNT,
  WEEK_TIMELINE_HOUR_END,
  WEEK_TIMELINE_HOUR_START,
  WEEK_TIMELINE_MIN_WIDTH,
  WEEK_TIMELINE_ROW_HEIGHT,
  WEEK_TIMELINE_TIME_AXIS_WIDTH,
  WEEK_TIMELINE_TOTAL_HEIGHT,
} from './weekTimelineLayout';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { Task } from '@/lib/ipc/tasks/models';

function event(overrides: Partial<UnifiedCalendarEvent>): UnifiedCalendarEvent {
  return {
    id: 'event-1',
    title: 'Calendar event',
    start_date: '2026-06-19',
    end_date: '2026-06-19',
    start_time: '09:00',
    end_time: '10:00',
    all_day: false,
    location: null,
    notes: null,
    color: null,
    recurrence: null,
    exceptions: [],
    created_at: '2026-06-19T09:00:00Z',
    updated_at: '2026-06-19T09:00:00Z',
    kind: 'canonical',
    editable: true,
    event_type: 'event',
    attendees_json: null,
    ...overrides,
  } as UnifiedCalendarEvent;
}

function task(overrides: Partial<Task>): Task {
  return {
    id: 'task-1',
    title: 'Timed task',
    status: 'open',
    due_time: '11:00',
    estimated_minutes: 45,
    ...overrides,
  } as Task;
}

describe('week timeline layout', () => {
  it('renders a full-day scrollable grid', () => {
    expect(WEEK_TIMELINE_HOUR_START).toBe(0);
    expect(WEEK_TIMELINE_HOUR_END).toBe(24);
    expect(WEEK_TIMELINE_HOUR_COUNT).toBe(24);
    expect(WEEK_TIMELINE_ROW_HEIGHT).toBe(DAY_TIMELINE_ROW_HEIGHT);
    expect(WEEK_TIMELINE_TOTAL_HEIGHT).toBe(24 * WEEK_TIMELINE_ROW_HEIGHT);
  });

  it('keeps week columns readable by scrolling horizontally before compression', () => {
    expect(WEEK_TIMELINE_DAY_MIN_WIDTH).toBeGreaterThanOrEqual(112);
    expect(WEEK_TIMELINE_MIN_WIDTH).toBe(
      WEEK_TIMELINE_TIME_AXIS_WIDTH + WEEK_TIMELINE_DAY_MIN_WIDTH * 7,
    );
  });

  it('positions early-morning events in their real time slot', () => {
    const fourTwentyTwo = 4 * 60 + 22;

    expect(weekTimelineMinutesToTop(fourTwentyTwo)).toBeCloseTo(
      (fourTwentyTwo / 60) * WEEK_TIMELINE_ROW_HEIGHT,
    );

    expect(weekTimelineGeometry('04:22', '06:22', 30)).toEqual({
      top: weekTimelineMinutesToTop(fourTwentyTwo),
      height: 2 * WEEK_TIMELINE_ROW_HEIGHT,
    });
  });

  it('opens early travel days at midnight so users can scroll through pre-dawn context', () => {
    expect(
      weekTimelineInitialScrollTop({
        currentMinutes: 13 * 60,
        selectedDayItems: [
          { id: 'standup', start: '09:05', end: '10:05', fallbackDurationMinutes: 30 },
          { id: 'airport', start: '04:22', end: '06:22', fallbackDurationMinutes: 30 },
        ],
      }),
    ).toBe(0);
  });

  it('anchors ordinary days just above the earliest timed item', () => {
    expect(
      weekTimelineInitialScrollTop({
        currentMinutes: 13 * 60,
        selectedDayItems: [
          { id: 'standup', start: '09:05', end: '10:05', fallbackDurationMinutes: 30 },
          { id: 'planning', start: '11:00', end: '11:30', fallbackDurationMinutes: 30 },
        ],
      }),
    ).toBeCloseTo(((9 * 60 + 5 - 30) / 60) * WEEK_TIMELINE_ROW_HEIGHT);
  });

  it('treats 08:00 as the ordinary-day scroll boundary', () => {
    expect(
      weekTimelineInitialScrollTop({
        currentMinutes: 13 * 60,
        selectedDayItems: [
          { id: 'early-call', start: '07:59', end: '08:15', fallbackDurationMinutes: 30 },
        ],
      }),
    ).toBe(0);

    expect(
      weekTimelineInitialScrollTop({
        currentMinutes: 13 * 60,
        selectedDayItems: [
          { id: 'breakfast', start: '08:00', end: '08:30', fallbackDurationMinutes: 30 },
        ],
      }),
    ).toBeCloseTo(7.5 * WEEK_TIMELINE_ROW_HEIGHT);
  });

  it('uses timed tasks as early-travel scroll anchors', () => {
    const anchors = weekTimelineScrollAnchorItems({
      selectedDate: '2026-06-19',
      weekDates: ['2026-06-19'],
      eventsByDate: {},
      tasksByDate: {
        '2026-06-19': [task({ id: 'airport-task', due_time: '04:22' })],
      },
    });

    expect(anchors.map((item) => item.id)).toEqual(['airport-task']);
    expect(
      weekTimelineInitialScrollTop({
        currentMinutes: 13 * 60,
        selectedDayItems: anchors,
      }),
    ).toBe(0);
  });

  it('falls back to current time when the selected day has no timed items', () => {
    expect(
      weekTimelineInitialScrollTop({
        currentMinutes: 13 * 60,
        selectedDayItems: [],
      }),
    ).toBeCloseTo(12 * WEEK_TIMELINE_ROW_HEIGHT);
  });

  it('uses the selected day as the scroll anchor when a day is selected', () => {
    const anchors = weekTimelineScrollAnchorItems({
      selectedDate: '2026-06-19',
      weekDates: ['2026-06-18', '2026-06-19'],
      eventsByDate: {
        '2026-06-18': [event({ id: 'prev-day-flight', start_time: '04:22', end_time: '06:22' })],
        '2026-06-19': [event({ id: 'selected-standup', start_time: '09:05', end_time: '10:05' })],
      },
      tasksByDate: {},
    });

    expect(anchors.map((item) => item.id)).toEqual(['selected-standup']);
  });

  it('falls back to the whole week when no day is selected', () => {
    const anchors = weekTimelineScrollAnchorItems({
      selectedDate: null,
      weekDates: ['2026-06-18', '2026-06-19'],
      eventsByDate: {
        '2026-06-18': [event({ id: 'airport', start_time: '04:22', end_time: '06:22' })],
        '2026-06-19': [event({ id: 'standup', start_time: '09:05', end_time: '10:05' })],
      },
      tasksByDate: {
        '2026-06-19': [task({ id: 'timed-task', due_time: '08:30' })],
      },
    });

    expect(anchors.map((item) => item.id)).toEqual(['airport', 'standup', 'timed-task']);
    expect(
      weekTimelineInitialScrollTop({
        currentMinutes: 13 * 60,
        selectedDayItems: anchors,
      }),
    ).toBe(0);
  });

  it('keeps independent overlap clusters at their natural width', () => {
    const slots = computeWeekTimelineSlots([
      { id: 'flight', start: '06:22', end: '08:26', fallbackDurationMinutes: 30 },
      { id: 'buffer', start: '08:26', end: '08:56', fallbackDurationMinutes: 30 },
      { id: 'meeting', start: '09:05', end: '10:05', fallbackDurationMinutes: 30 },
    ]);

    expect(slots.get('flight')).toEqual({ index: 0, count: 1 });
    expect(slots.get('buffer')).toEqual({ index: 0, count: 1 });
    expect(slots.get('meeting')).toEqual({ index: 0, count: 1 });
  });

  it('assigns shared slots for overlapping events and timed tasks only within that cluster', () => {
    const slots = computeWeekTimelineSlots([
      { id: 'event-a', start: '09:00', end: '10:00', fallbackDurationMinutes: 30 },
      { id: 'task-a', start: '09:30', end: null, fallbackDurationMinutes: 45 },
      { id: 'event-b', start: '14:00', end: '14:30', fallbackDurationMinutes: 30 },
    ]);

    expect(slots.get('event-a')).toEqual({ index: 0, count: 2 });
    expect(slots.get('task-a')).toEqual({ index: 1, count: 2 });
    expect(slots.get('event-b')).toEqual({ index: 0, count: 1 });
  });
});
