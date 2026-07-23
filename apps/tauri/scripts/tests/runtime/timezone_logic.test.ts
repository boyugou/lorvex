import assert from 'node:assert/strict';
import test from 'node:test';

import { decideTimezoneMaintenance } from '../../../app/src/app-shell/main-window/runtime/useBackgroundMaintenance.logic';
import { getRawSystemTimezone, normalizeTimezonePreference, resolveTimezoneOptions, isValidTimezone } from '../../../app/src/lib/dates/timezone';
import { resolveConfiguredTimezoneState } from '../../../app/src/lib/dayContext';

const IntlWithSupportedValues = Intl as typeof Intl & {
  supportedValuesOf?: (key: 'timeZone') => string[];
};

test('normalizeTimezonePreference keeps valid values and fails closed to the system timezone or UTC', () => {
  assert.equal(normalizeTimezonePreference('America/New_York', 'America/Los_Angeles'), 'America/New_York');
  assert.equal(normalizeTimezonePreference('not/a-timezone', 'America/Los_Angeles'), 'America/Los_Angeles');
  assert.equal(normalizeTimezonePreference(null, 'not/a-timezone'), 'UTC');
});

test('isValidTimezone rejects raw UTC offset identifiers even when Intl accepts them', () => {
  assert.equal(isValidTimezone('America/New_York'), true);
  assert.equal(isValidTimezone('+01:00'), false);
  assert.equal(isValidTimezone('-0500'), false);
});

test('getRawSystemTimezone preserves the host-reported timezone and does not coerce blanks to UTC', () => {
  const originalResolvedOptions = Intl.DateTimeFormat.prototype.resolvedOptions;

  Intl.DateTimeFormat.prototype.resolvedOptions = function patchedResolvedOptions() {
    return {
      ...originalResolvedOptions.call(this),
      timeZone: '',
    };
  };

  try {
    assert.equal(getRawSystemTimezone(), null);
  } finally {
    Intl.DateTimeFormat.prototype.resolvedOptions = originalResolvedOptions;
  }
});

test('resolveTimezoneOptions always preserves UTC even when supportedValuesOf omits it', () => {
  const original = IntlWithSupportedValues.supportedValuesOf;
  IntlWithSupportedValues.supportedValuesOf = () => ['America/Los_Angeles', 'Europe/Berlin'];

  try {
    assert.deepEqual(resolveTimezoneOptions('Europe/Berlin', 'America/Los_Angeles'), [
      'UTC',
      'America/Los_Angeles',
      'Europe/Berlin',
    ]);
  } finally {
    IntlWithSupportedValues.supportedValuesOf = original;
  }
});

test('resolveTimezoneOptions prepends a valid selected timezone and appends a missing system timezone without duplicates', () => {
  const original = IntlWithSupportedValues.supportedValuesOf;
  IntlWithSupportedValues.supportedValuesOf = () => ['UTC', 'Europe/Berlin'];

  try {
    assert.deepEqual(resolveTimezoneOptions('Asia/Tokyo', 'America/Los_Angeles'), [
      'Asia/Tokyo',
      'UTC',
      'Europe/Berlin',
      'America/Los_Angeles',
    ]);
  } finally {
    IntlWithSupportedValues.supportedValuesOf = original;
  }
});

test('resolveConfiguredTimezoneState distinguishes missing preferences from malformed or invalid stored values', () => {
  assert.deepEqual(resolveConfiguredTimezoneState(null), {
    timezone: Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC',
    invalidStoredPreference: false,
  });

  assert.deepEqual(resolveConfiguredTimezoneState('\"America/New_York\"'), {
    timezone: 'America/New_York',
    invalidStoredPreference: false,
  });

  const malformed = resolveConfiguredTimezoneState('{oops');
  assert.equal(malformed.invalidStoredPreference, true);

  const invalidTimezone = resolveConfiguredTimezoneState('\"+01:00\"');
  assert.equal(invalidTimezone.invalidStoredPreference, true);

  const jsonNull = resolveConfiguredTimezoneState('null');
  assert.equal(jsonNull.invalidStoredPreference, true);
});

test('decideTimezoneMaintenance canonicalizes system timezone and distinguishes seed, repair, update, and noop flows', () => {
  assert.deepEqual(decideTimezoneMaintenance(null, 'America/Los_Angeles'), {
    type: 'seed',
    timezone: 'America/Los_Angeles',
  });

  assert.deepEqual(decideTimezoneMaintenance('null', 'America/Los_Angeles'), {
    type: 'repair',
    timezone: 'America/Los_Angeles',
  });

  assert.deepEqual(decideTimezoneMaintenance('\"America/New_York\"', 'America/Los_Angeles'), {
    type: 'update',
    previousTimezone: 'America/New_York',
    timezone: 'America/Los_Angeles',
  });

  assert.deepEqual(decideTimezoneMaintenance('\"America/Los_Angeles\"', 'America/Los_Angeles'), {
    type: 'noop',
  });

  assert.deepEqual(decideTimezoneMaintenance('\"America/New_York\"', '+01:00'), {
    type: 'noop',
  });

  assert.deepEqual(decideTimezoneMaintenance('\"America/New_York\"', null), {
    type: 'noop',
  });
});
