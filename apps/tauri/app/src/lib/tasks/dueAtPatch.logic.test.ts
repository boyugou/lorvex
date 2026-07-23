import { describe, expect, it } from 'vitest';

import { buildDueDatePatch, buildDueTimePatch } from './dueAtPatch.logic';

const task = (due_date: string | null, due_time: string | null) => ({
  due_date,
  due_time,
});

describe('due-at patch helpers', () => {
  it('clears due_time when clearing the due_date', () => {
    expect(buildDueDatePatch(task('2026-04-15', '09:30'), null)).toEqual({
      due_date: null,
      due_time: null,
    });
  });

  it('sets fallback due_date when adding due_time to an undated task', () => {
    expect(buildDueTimePatch(task(null, null), '09:30', '2026-04-15')).toEqual({
      due_date: '2026-04-15',
      due_time: '09:30',
    });
  });

  it('does not rewrite due_date when changing time on a dated task', () => {
    expect(buildDueTimePatch(task('2026-04-15', '08:00'), '09:30', '2026-04-16')).toEqual({
      due_time: '09:30',
    });
  });
});
