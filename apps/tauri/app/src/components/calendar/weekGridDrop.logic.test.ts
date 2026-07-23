import { describe, expect, it } from 'vitest';
import { resolveWeekGridDrop, resolveWeekTimelineDropTime } from './weekGridDrop.logic';
import { encodeCalendarTaskDrag } from './calendarViewUtils';
import {
  WEEK_TIMELINE_ROW_HEIGHT,
  WEEK_TIMELINE_TOTAL_HEIGHT,
} from './week-timeline/weekTimelineLayout';

describe('resolveWeekTimelineDropTime', () => {
  it('maps a mid-grid Y to the snapped time at that row', () => {
    // 9 full rows down = 09:00 on a midnight-anchored 60-min grid.
    expect(resolveWeekTimelineDropTime(9 * WEEK_TIMELINE_ROW_HEIGHT)).toEqual({
      top: 9 * WEEK_TIMELINE_ROW_HEIGHT,
      timeStr: '09:00',
    });
  });

  it('snaps a between-rows Y to the nearest 15-minute slot', () => {
    // A nudge above the 9:00 line rounds back to 09:00; a nudge past the
    // 7.5-minute midpoint of the row rounds forward to 09:15.
    const ninePx = 9 * WEEK_TIMELINE_ROW_HEIGHT;
    const oneMinutePx = WEEK_TIMELINE_ROW_HEIGHT / 60;
    expect(resolveWeekTimelineDropTime(ninePx + 3 * oneMinutePx).timeStr).toBe('09:00');
    expect(resolveWeekTimelineDropTime(ninePx + 10 * oneMinutePx).timeStr).toBe('09:15');
  });

  it('clamps a negative / above-grid Y to the first slot (00:00)', () => {
    expect(resolveWeekTimelineDropTime(-500)).toEqual({ top: 0, timeStr: '00:00' });
  });

  it('clamps a below-grid Y to the last usable slot (23:45)', () => {
    const result = resolveWeekTimelineDropTime(WEEK_TIMELINE_TOTAL_HEIGHT + 999);
    expect(result.timeStr).toBe('23:45');
    // The clamped slot's top stays inside the grid (never the full 24:00 edge).
    expect(result.top).toBeLessThan(WEEK_TIMELINE_TOTAL_HEIGHT);
  });
});

describe('resolveWeekGridDrop', () => {
  it('reschedules a different-day drop with the column date + inferred time', () => {
    const raw = encodeCalendarTaskDrag('task-1', '2026-04-20', true, '08:00');
    expect(resolveWeekGridDrop(raw, '2026-04-22', '10:30', true)).toEqual({
      kind: 'reschedule',
      taskId: 'task-1',
      newDate: '2026-04-22',
      oldDate: '2026-04-20',
      oldTime: '08:00',
      dueTime: '10:30',
      hasPlannedDate: true,
    });
  });

  it('ignores a same-day drop at the task’s existing time (true no-op)', () => {
    const raw = encodeCalendarTaskDrag('task-1', '2026-04-22', true, '09:00');
    expect(resolveWeekGridDrop(raw, '2026-04-22', '09:00', true)).toEqual({ kind: 'ignore' });
  });

  it('reschedules a same-day drop at a different inferred time (re-time)', () => {
    const raw = encodeCalendarTaskDrag('task-1', '2026-04-22', true, '09:00');
    expect(resolveWeekGridDrop(raw, '2026-04-22', '14:15', true)).toEqual({
      kind: 'reschedule',
      taskId: 'task-1',
      newDate: '2026-04-22',
      oldDate: '2026-04-22',
      oldTime: '09:00',
      dueTime: '14:15',
      hasPlannedDate: true,
    });
  });

  it('reschedules a previously-untimed task (null oldTime) dropped at a time', () => {
    const raw = encodeCalendarTaskDrag('task-1', '2026-04-22', false, null);
    expect(resolveWeekGridDrop(raw, '2026-04-22', '07:30', true)).toEqual({
      kind: 'reschedule',
      taskId: 'task-1',
      newDate: '2026-04-22',
      oldDate: '2026-04-22',
      oldTime: null,
      dueTime: '07:30',
      hasPlannedDate: false,
    });
  });

  it('reschedules a drop whose source had a null oldDate', () => {
    const raw = encodeCalendarTaskDrag('task-1', null, false, null);
    expect(resolveWeekGridDrop(raw, '2026-04-22', '12:00', true)).toEqual({
      kind: 'reschedule',
      taskId: 'task-1',
      newDate: '2026-04-22',
      oldDate: null,
      oldTime: null,
      dueTime: '12:00',
      hasPlannedDate: false,
    });
  });

  it('ignores when the consumer did not wire a reschedule handler', () => {
    const raw = encodeCalendarTaskDrag('task-1', '2026-04-20', true, '08:00');
    expect(resolveWeekGridDrop(raw, '2026-04-22', '10:00', false)).toEqual({ kind: 'ignore' });
  });

  it('ignores when the payload is invalid JSON', () => {
    expect(resolveWeekGridDrop('not-json', '2026-04-22', '10:00', true)).toEqual({ kind: 'ignore' });
  });

  it('ignores when the payload has the wrong shape', () => {
    expect(resolveWeekGridDrop(JSON.stringify({ foo: 'bar' }), '2026-04-22', '10:00', true)).toEqual({
      kind: 'ignore',
    });
  });

  it('ignores when the dataTransfer payload is empty (no MIME data)', () => {
    expect(resolveWeekGridDrop('', '2026-04-22', '10:00', true)).toEqual({ kind: 'ignore' });
  });

  it('treats an oldTime-less legacy payload as untimed and reschedules', () => {
    // An encoder that omits oldTime decodes to oldTime=null, so a drop at any
    // time differs from null and reschedules rather than swallowing.
    const raw = JSON.stringify({ id: 'task-1', oldDate: '2026-04-22', hasPlannedDate: false });
    expect(resolveWeekGridDrop(raw, '2026-04-22', '09:00', true)).toEqual({
      kind: 'reschedule',
      taskId: 'task-1',
      newDate: '2026-04-22',
      oldDate: '2026-04-22',
      oldTime: null,
      dueTime: '09:00',
      hasPlannedDate: false,
    });
  });
});
