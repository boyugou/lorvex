import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import {
  formatWeekTimelineDayLabel,
  parseWeekTimelineDayNumberLabel,
  WEEK_TIMELINE_ROW_HEIGHT,
  weekTimelineEventGeometry,
  weekTimelineInitialScrollTopForItems,
  weekTimelineMinutesToOffset,
  weekTimelineScrollAnchorItems,
} from '../../../app/src/components/upcoming/WeekTimeline.logic';

const t = (key: string) => key;

test('parseWeekTimelineDayNumberLabel accepts only canonical YYYY-MM-DD day segments', () => {
  assert.equal(parseWeekTimelineDayNumberLabel('2026-04-01'), '1');
  assert.equal(parseWeekTimelineDayNumberLabel('2026-04-09'), '9');
  assert.equal(parseWeekTimelineDayNumberLabel('2026-04-31'), '31');

  for (const value of ['2026-04-00', '2026-04-32', '2026-04-1', '2026-04-1x', '2026-4-01', 'not-a-date']) {
    assert.equal(parseWeekTimelineDayNumberLabel(value), '');
  }
});

test('formatWeekTimelineDayLabel preserves today and tomorrow labels while using strict day labels', () => {
  assert.deepEqual(formatWeekTimelineDayLabel('2026-04-24', '2026-04-24', 'en-US', t), {
    label: 'upcoming.today',
    dayNum: '24',
  });
  assert.deepEqual(formatWeekTimelineDayLabel('2026-04-25', '2026-04-24', 'en-US', t), {
    label: 'upcoming.tomorrow',
    dayNum: '25',
  });

  assert.equal(formatWeekTimelineDayLabel('2026-04-26', '2026-04-24', 'en-US', t).label, 'Sun');
});

test('WeekTimeline component keeps date-string day parsing out of JSX', () => {
  const source = readFileSync('app/src/components/upcoming/WeekTimeline.tsx', 'utf8');
  assert.doesNotMatch(source, /parseInt|Number\.parseInt/);
  assert.doesNotMatch(source, /dateStr\.slice\(8\)/);
});

test('WeekTimeline preserves readable day columns on mobile by scrolling horizontally', () => {
  const source = readFileSync('app/src/components/upcoming/WeekTimeline.tsx', 'utf8');
  assert.match(source, /overflow-x-auto/);
  assert.match(source, /overscroll-x-contain/);
  assert.match(source, /min-w-\[52rem\]/);
});

test('WeekTimeline positions early-morning events in full-day coordinates', () => {
  const fourTwentyTwo = 4 * 60 + 22;

  assert.equal(
    weekTimelineMinutesToOffset(fourTwentyTwo),
    (fourTwentyTwo / 60) * WEEK_TIMELINE_ROW_HEIGHT,
  );
  assert.deepEqual(weekTimelineEventGeometry('04:22', '06:22'), {
    top: weekTimelineMinutesToOffset(fourTwentyTwo),
    height: 2 * WEEK_TIMELINE_ROW_HEIGHT,
  });
});

test('WeekTimeline keeps inverted event ranges to a compact readable block', () => {
  assert.deepEqual(weekTimelineEventGeometry('06:22', '04:22'), {
    top: weekTimelineMinutesToOffset(6 * 60 + 22),
    height: 20,
  });
});

test('WeekTimeline initial scroll anchors early travel days at midnight', () => {
  assert.equal(
    weekTimelineInitialScrollTopForItems({
      currentMinutes: 13 * 60,
      timedItems: [
        { id: 'standup', startTime: '09:05' },
        { id: 'airport', startTime: '04:22' },
      ],
    }),
    0,
  );
});

test('WeekTimeline uses the whole visible week as its initial scroll anchor set', () => {
  const anchors = weekTimelineScrollAnchorItems({
    weekDates: ['2026-06-18', '2026-06-19'],
    eventsByDate: {
      '2026-06-18': [
        {
          id: 'airport',
          title: 'Airport',
          start_date: '2026-06-18',
          end_date: '2026-06-18',
          start_time: '04:22',
          end_time: '06:22',
          all_day: false,
        },
      ],
    },
    tasksByDate: {
      '2026-06-19': [
        {
          id: 'standup-task',
          status: 'open',
          due_time: '09:05',
        },
      ],
    },
  } as never);

  assert.deepEqual(anchors, [
    { id: 'airport', startTime: '04:22' },
    { id: 'standup-task', startTime: '09:05' },
  ]);
});
