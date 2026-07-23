import { describe, expect, it } from 'vitest';

import {
  resolveWeekAllDaySegments,
  resolveWeekAllDayVisibleItems,
  weekAllDaySegmentHitTargets,
  WEEK_ALL_DAY_VISIBLE_ITEM_LIMIT,
} from './WeekAllDayStrip.logic';

describe('WeekAllDayStrip logic', () => {
  it('caps visible all-day rows and reports hidden overflow', () => {
    const items = [
      { id: 'room' },
      { id: 'flag-day' },
      { id: 'holiday' },
      { id: 'regional-holiday' },
      { id: 'travel-note' },
    ];

    expect(resolveWeekAllDayVisibleItems(items)).toEqual({
      visible: items.slice(0, WEEK_ALL_DAY_VISIBLE_ITEM_LIMIT),
      hiddenCount: 2,
    });
  });

  it('does not report overflow under the row cap', () => {
    const items = [{ id: 'room' }, { id: 'holiday' }];

    expect(resolveWeekAllDayVisibleItems(items)).toEqual({
      visible: items,
      hiddenCount: 0,
    });
  });

  it('deduplicates and spans multi-day all-day events across the visible week', () => {
    const weekDates = [
      '2026-06-14',
      '2026-06-15',
      '2026-06-16',
      '2026-06-17',
      '2026-06-18',
      '2026-06-19',
      '2026-06-20',
    ];
    const room = {
      id: 'room',
      start_date: '2026-06-14',
      end_date: '2026-06-20',
    };

    const segments = resolveWeekAllDaySegments({
      weekDates,
      eventsByDate: Object.fromEntries(weekDates.map((date) => [date, [room]])),
    });

    expect(segments.visible).toEqual([
      { key: 'room:2026-06-14:2026-06-20', item: room, startIndex: 0, endIndex: 6, lane: 0 },
    ]);
    expect(segments.hiddenByDate).toEqual({});
  });

  it('clamps all-day spans that begin before the visible week', () => {
    const event = {
      id: 'retreat',
      start_date: '2026-06-10',
      end_date: '2026-06-16',
    };

    expect(
      resolveWeekAllDaySegments({
        weekDates: ['2026-06-14', '2026-06-15', '2026-06-16'],
        eventsByDate: {
          '2026-06-14': [event],
          '2026-06-15': [event],
          '2026-06-16': [event],
        },
      }).visible,
    ).toEqual([
      { key: 'retreat:2026-06-10:2026-06-16', item: event, startIndex: 0, endIndex: 2, lane: 0 },
    ]);
  });

  it('keeps recurring all-day occurrences with the same event id separate', () => {
    const first = {
      id: 'daily-recurring',
      start_date: '2026-06-14',
      end_date: '2026-06-14',
    };
    const second = {
      id: 'daily-recurring',
      start_date: '2026-06-15',
      end_date: '2026-06-15',
    };

    const segments = resolveWeekAllDaySegments({
      weekDates: ['2026-06-14', '2026-06-15'],
      eventsByDate: {
        '2026-06-14': [first],
        '2026-06-15': [second],
      },
    });

    expect(segments.visible.map((segment) => segment.key)).toEqual([
      'daily-recurring:2026-06-14:2026-06-14',
      'daily-recurring:2026-06-15:2026-06-15',
    ]);
    expect(segments.visible.map((segment) => [segment.startIndex, segment.endIndex, segment.lane])).toEqual([
      [0, 0, 0],
      [1, 1, 0],
    ]);
  });

  it('reports hidden all-day overflow per covered date', () => {
    const weekDates = ['2026-06-14', '2026-06-15'];
    const events = Array.from({ length: 4 }, (_, index) => ({
      id: `event-${index}`,
      start_date: '2026-06-14',
      end_date: '2026-06-15',
    }));

    const segments = resolveWeekAllDaySegments({
      weekDates,
      eventsByDate: {
        '2026-06-14': events,
        '2026-06-15': events,
      },
      limit: 3,
    });

    expect(segments.visible).toHaveLength(3);
    expect(segments.hiddenByDate).toEqual({
      '2026-06-14': 1,
      '2026-06-15': 1,
    });
  });

  it('expands a visible all-day segment into one hit target per covered date', () => {
    const event = {
      id: 'room',
      start_date: '2026-06-14',
      end_date: '2026-06-16',
    };
    const weekDates = ['2026-06-14', '2026-06-15', '2026-06-16'];
    const [segment] = resolveWeekAllDaySegments({
      weekDates,
      eventsByDate: Object.fromEntries(weekDates.map((date) => [date, [event]])),
    }).visible;

    expect(segment).toBeDefined();
    expect(weekAllDaySegmentHitTargets(segment!, weekDates)).toEqual([
      {
        key: 'room:2026-06-14:2026-06-16:2026-06-14',
        item: event,
        date: '2026-06-14',
        index: 0,
        isStart: true,
        isEnd: false,
      },
      {
        key: 'room:2026-06-14:2026-06-16:2026-06-15',
        item: event,
        date: '2026-06-15',
        index: 1,
        isStart: false,
        isEnd: false,
      },
      {
        key: 'room:2026-06-14:2026-06-16:2026-06-16',
        item: event,
        date: '2026-06-16',
        index: 2,
        isStart: false,
        isEnd: true,
      },
    ]);
  });
});
