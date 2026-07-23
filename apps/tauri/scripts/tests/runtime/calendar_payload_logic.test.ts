import assert from 'node:assert/strict';
import test from 'node:test';

import {
  decodeCalendarTaskDrag,
  recurrenceFromRaw,
  resolveWeekStartAnchor,
} from '../../../app/src/components/calendar/calendarViewUtils';
import {
  normalizeRecurrenceIntervalInput,
  normalizeRecurrenceIntervalValue,
  parseRecurrence,
} from '../../../app/src/components/task-detail/metadata-editor/shared';

test('parseRecurrence accepts valid payloads and rejects malformed ones', () => {
  assert.deepEqual(
    parseRecurrence('{"FREQ":"WEEKLY","INTERVAL":2,"BYDAY":["MO","WE"],"UNTIL":"2026-06-01"}'),
    {
      freq: 'WEEKLY',
      editable: true,
      interval: 2,
      byday: ['MO', 'WE'],
      until: '2026-06-01',
    },
  );
  assert.equal(parseRecurrence('{oops'), null);
  assert.equal(parseRecurrence('{"FREQ":"INVALID"}'), null);
  assert.equal(parseRecurrence('{"FREQ":"WEEKLY","BYDAY":["MO",3,"ZZ"]}'), null);
  assert.equal(parseRecurrence('{"FREQ":"WEEKLY","INTERVAL":1.5}'), null);
  assert.equal(parseRecurrence('{"FREQ":"WEEKLY","INTERVAL":100}'), null);
  assert.equal(parseRecurrence('{"FREQ":"WEEKLY","UNTIL":"tomorrow"}'), null);
  assert.deepEqual(
    parseRecurrence('{"FREQ":"WEEKLY","COUNT":2}'),
    {
      freq: 'WEEKLY',
      editable: false,
      interval: undefined,
      byday: undefined,
      until: undefined,
    },
  );
});

test('task recurrence interval normalizers fail closed to the editor range', () => {
  assert.equal(normalizeRecurrenceIntervalInput('2'), 2);
  assert.equal(normalizeRecurrenceIntervalInput(' 12 '), 12);
  assert.equal(normalizeRecurrenceIntervalInput(''), 1);
  assert.equal(normalizeRecurrenceIntervalInput('0'), 1);
  assert.equal(normalizeRecurrenceIntervalInput('100'), 99);

  assert.equal(normalizeRecurrenceIntervalInput('2x'), 1);
  assert.equal(normalizeRecurrenceIntervalInput('1.5'), 1);
  assert.equal(normalizeRecurrenceIntervalInput('1e2'), 1);

  assert.equal(normalizeRecurrenceIntervalValue(3.9), 3);
  assert.equal(normalizeRecurrenceIntervalValue(Number.NaN), 1);
});

test('decodeCalendarTaskDrag accepts structured payloads and rejects malformed payloads', () => {
  assert.deepEqual(
    decodeCalendarTaskDrag('{"id":"task-1","oldDate":"2026-04-21","hasPlannedDate":true}'),
    { id: 'task-1', oldDate: '2026-04-21', oldTime: null, hasPlannedDate: true },
  );
  assert.equal(decodeCalendarTaskDrag('task-raw'), null);
  assert.equal(decodeCalendarTaskDrag(''), null);
  assert.equal(decodeCalendarTaskDrag('{"id":"task-1","oldDate":"2026-04-21","hasPlannedDate":true,"debug":true}'), null);
  assert.equal(decodeCalendarTaskDrag('{"id":" task-1 ","oldDate":"2026-04-21","hasPlannedDate":true}'), null);
  assert.equal(decodeCalendarTaskDrag('{"id":"task-1","oldDate":"tomorrow","hasPlannedDate":true}'), null);
  assert.equal(decodeCalendarTaskDrag('{"id":"task-1","oldDate":"2026-04-21","hasPlannedDate":"true"}'), null);
});

test('recurrenceFromRaw fails closed and supplies weekly fallback weekdays', () => {
  assert.deepEqual(
    recurrenceFromRaw('{"FREQ":"WEEKLY","BYDAY":["WE"]}', '2026-04-21'),
    {
      preset: 'weekly',
      interval: 1,
      byday: ['WE'],
      endCondition: 'never',
      until: '',
    },
  );
  assert.deepEqual(
    recurrenceFromRaw('{"FREQ":"WEEKLY","BYDAY":[]}', '2026-04-21'),
    {
      preset: 'weekly',
      interval: 1,
      byday: ['TU'],
      endCondition: 'never',
      until: '',
    },
  );
  assert.deepEqual(
    recurrenceFromRaw('{"FREQ":"WEEKLY","BYDAY":["WE",3,"ZZ"]}', '2026-04-21'),
    {
      preset: 'none',
      interval: 1,
      byday: ['TU'],
      endCondition: 'never',
      until: '',
    },
  );
  assert.deepEqual(
    recurrenceFromRaw('{oops', '2026-04-21'),
    {
      preset: 'none',
      interval: 1,
      byday: ['TU'],
      endCondition: 'never',
      until: '',
    },
  );
  assert.deepEqual(
    recurrenceFromRaw('{"FREQ":"WEEKLY","INTERVAL":1.5}', '2026-04-21'),
    {
      preset: 'none',
      interval: 1,
      byday: ['TU'],
      endCondition: 'never',
      until: '',
    },
  );
  assert.deepEqual(
    recurrenceFromRaw('{"FREQ":"WEEKLY","UNTIL":"2026-02-30"}', '2026-04-21'),
    {
      preset: 'none',
      interval: 1,
      byday: ['TU'],
      endCondition: 'never',
      until: '',
    },
  );
  assert.deepEqual(
    recurrenceFromRaw('{"FREQ":"WEEKLY","COUNT":2}', '2026-04-21'),
    {
      preset: 'advanced',
      interval: 1,
      byday: [],
      endCondition: 'never',
      until: '',
    },
  );
});

test('resolveWeekStartAnchor re-anchors from the active date instead of the previous week head', () => {
  assert.equal(resolveWeekStartAnchor('2026-04-22', '2026-04-22', 1), '2026-04-20');
  assert.equal(resolveWeekStartAnchor(null, '2026-04-22', 1), '2026-04-20');
  assert.equal(resolveWeekStartAnchor('2026-04-22', '2026-04-22', 6), '2026-04-18');
});
