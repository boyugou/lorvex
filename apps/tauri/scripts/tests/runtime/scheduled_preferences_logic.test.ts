import assert from 'node:assert/strict';
import test from 'node:test';

import {
  normalizeScheduledTimePreference,
  normalizeScheduledWeekdayPreference,
} from '../../../app/src/lib/scheduledPreferences.logic';
import {
  parseTimePreference,
  parseWeekdayPreference,
} from '../../../app/src/lib/notifications/preferences';
import {
  DEFAULT_MORNING_BRIEFING_TIME,
  DEFAULT_WEEKLY_REVIEW_DAY,
  DEFAULT_WEEKLY_REVIEW_TIME,
  DEFAULT_WORKING_HOURS_END,
  DEFAULT_WORKING_HOURS_START,
  normalizeAdvancedPreferenceDraft,
  normalizeWorkingHoursPreference,
} from '../../../app/src/components/settings/controller/general/preferences/normalization';

test('scheduled preference helpers trim canonical values and reject malformed time and weekday inputs', () => {
  assert.equal(normalizeScheduledTimePreference(' 09:30 ', '08:00'), '09:30');
  assert.equal(normalizeScheduledTimePreference('24:00', '08:00'), '08:00');
  assert.equal(normalizeScheduledTimePreference('9:30', '08:00'), '08:00');
  assert.equal(normalizeScheduledTimePreference(930, '08:00'), '08:00');

  assert.equal(normalizeScheduledWeekdayPreference(' Monday ', 'friday'), 'monday');
  assert.equal(normalizeScheduledWeekdayPreference('FUNDAY', 'friday'), 'friday');
  assert.equal(normalizeScheduledWeekdayPreference(null, 'friday'), 'friday');
});

test('notification scheduled preference parsers stay aligned with the shared helper contract', () => {
  assert.equal(parseTimePreference('" 07:15 "', '08:00'), '07:15');
  assert.equal(parseTimePreference('"7:15"', '08:00'), '08:00');
  assert.equal(parseTimePreference('false', '08:00'), '08:00');
  assert.equal(parseTimePreference('{', '08:00'), '08:00');

  assert.equal(parseWeekdayPreference('" Tuesday "', 'friday'), 'tuesday');
  assert.equal(parseWeekdayPreference('"holiday"', 'friday'), 'friday');
  assert.equal(parseWeekdayPreference('3', 'friday'), 'friday');
  assert.equal(parseWeekdayPreference('{', 'friday'), 'friday');
});

test('advanced preference draft normalization reuses the shared schedule helpers while preserving timezone repair', () => {
  assert.deepEqual(
    normalizeAdvancedPreferenceDraft({
      timezone: '+01:00',
      systemTimezone: 'America/New_York',
      weeklyReviewDay: ' Tuesday ',
      weeklyReviewTime: ' 17:45 ',
      morningBriefingTime: '25:00',
    }),
    {
      timezone: 'America/New_York',
      weeklyReviewDay: 'tuesday',
      weeklyReviewTime: '17:45',
      morningBriefingTime: DEFAULT_MORNING_BRIEFING_TIME,
    },
  );

  assert.deepEqual(
    normalizeAdvancedPreferenceDraft({
      timezone: '',
      systemTimezone: 'UTC',
      weeklyReviewDay: 'holiday',
      weeklyReviewTime: '9:00',
      morningBriefingTime: ' 06:30 ',
    }),
    {
      timezone: 'UTC',
      weeklyReviewDay: DEFAULT_WEEKLY_REVIEW_DAY,
      weeklyReviewTime: DEFAULT_WEEKLY_REVIEW_TIME,
      morningBriefingTime: '06:30',
    },
  );
});

test('working-hours preference normalization requires a canonical complete time object', () => {
  assert.deepEqual(
    normalizeWorkingHoursPreference({
      start: '09:30',
      end: '17:45',
    }),
    {
      start: '09:30',
      end: '17:45',
    },
  );

  const defaults = {
    start: DEFAULT_WORKING_HOURS_START,
    end: DEFAULT_WORKING_HOURS_END,
  };
  assert.deepEqual(normalizeWorkingHoursPreference({ start: '9:30', end: '17:45' }), defaults);
  assert.deepEqual(normalizeWorkingHoursPreference({ start: '09:30' }), defaults);
  assert.deepEqual(
    normalizeWorkingHoursPreference({ start: '09:30', end: '17:45', debug: true }),
    defaults,
  );
  assert.deepEqual(normalizeWorkingHoursPreference(['09:30', '17:45']), defaults);
});
