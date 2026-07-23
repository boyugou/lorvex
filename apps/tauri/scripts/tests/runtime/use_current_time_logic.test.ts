import assert from 'node:assert/strict';
import test from 'node:test';

import { isEventPast } from '../../../app/src/lib/time/useCurrentTime';
import { addMinutesToTime, getCurrentHHMM } from '../../../app/src/lib/time/useCurrentTime.logic';

test('getCurrentHHMM formats a valid timezone using the requested clock rather than host locale defaults', () => {
  const now = new Date('2026-04-20T15:45:00Z');
  assert.equal(getCurrentHHMM('America/Los_Angeles', now), '08:45');
  assert.equal(getCurrentHHMM('Asia/Tokyo', now), '00:45');
});

test('getCurrentHHMM falls back to the system-local Date fields when timezone is invalid', () => {
  const now = new Date('2026-04-20T15:45:00Z');
  const expected = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
  assert.equal(getCurrentHHMM('Not/A_Real_Timezone', now), expected);
});

test('addMinutesToTime wraps across midnight', () => {
  assert.equal(addMinutesToTime('23:30', 60), '00:30');
  assert.equal(addMinutesToTime('00:05', 30), '00:35');
});

test('isEventPast uses end_time when present and all-day events are never past', () => {
  assert.equal(
    isEventPast({ start_time: '09:00', end_time: '10:30', all_day: false }, '10:29'),
    false,
  );
  assert.equal(
    isEventPast({ start_time: '09:00', end_time: '10:30', all_day: false }, '10:30'),
    true,
  );
  assert.equal(isEventPast({ start_time: '09:00', all_day: true }, '23:59'), false);
});

test('isEventPast synthesizes a one-hour duration when end_time is absent', () => {
  assert.equal(isEventPast({ start_time: '09:00', all_day: false }, '09:59'), false);
  assert.equal(isEventPast({ start_time: '09:00', all_day: false }, '10:00'), true);
});
