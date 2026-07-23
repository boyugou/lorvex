import assert from 'node:assert/strict';
import test from 'node:test';

import * as datePickerLogic from '../../../app/src/components/ui/DatePicker.logic';
import { parseYmd, ymdFromParts } from '../../../app/src/lib/dayContextMath';

test('date picker ymd parser accepts only canonical real calendar dates', () => {
  assert.deepEqual(parseYmd('2026-04-24'), {
    year: 2026,
    month: 3,
    day: 24,
  });
  assert.deepEqual(parseYmd('2028-02-29'), {
    year: 2028,
    month: 1,
    day: 29,
  });

  assert.equal(parseYmd('2026-4-24'), null);
  assert.equal(parseYmd('2026-04-24x'), null);
  assert.equal(parseYmd('2026-04-31'), null);
  assert.equal(parseYmd('2027-02-29'), null);
  assert.equal(parseYmd('0000-01-01'), null);
});

test('date picker ymd serializer emits canonical month and day fields', () => {
  assert.equal(ymdFromParts(2026, 0, 7), '2026-01-07');
  assert.equal(ymdFromParts(2026, 11, 31), '2026-12-31');
});

test('date picker day aria labels preserve calendar dates west of UTC', () => {
  const formatDatePickerDayAriaLabel = (
    datePickerLogic as unknown as {
      formatDatePickerDayAriaLabel?: (options: {
        ymd: string;
        locale: string;
        isToday: boolean;
        todayLabel: string;
      }) => string;
    }
  ).formatDatePickerDayAriaLabel;

  assert.equal(
    typeof formatDatePickerDayAriaLabel,
    'function',
    'DatePicker should expose a shared day aria-label formatter.',
  );

  const label = formatDatePickerDayAriaLabel({
    ymd: '2026-03-01',
    locale: 'en',
    isToday: false,
    todayLabel: 'Today',
  });

  assert.match(label, /March/);
  assert.match(label, /\b1\b/);
  assert.doesNotMatch(label, /February|28/);
});

test('date picker initial keyboard focus resolves an enabled day without a selected value', () => {
  const resolveDatePickerInitialFocusYmd = (
    datePickerLogic as unknown as {
      resolveDatePickerInitialFocusYmd?: (options: {
        value: string | null;
        todayYmd: string;
        minDate?: string;
      }) => string;
    }
  ).resolveDatePickerInitialFocusYmd;

  assert.equal(
    typeof resolveDatePickerInitialFocusYmd,
    'function',
    'DatePicker should resolve initial keyboard focus without depending on a selected value.',
  );

  assert.equal(
    resolveDatePickerInitialFocusYmd({
      value: null,
      todayYmd: '2026-05-08',
    }),
    '2026-05-08',
  );
  assert.equal(
    resolveDatePickerInitialFocusYmd({
      value: null,
      todayYmd: '2026-05-08',
      minDate: '2026-05-20',
    }),
    '2026-05-20',
  );
  assert.equal(
    resolveDatePickerInitialFocusYmd({
      value: '2026-05-10',
      todayYmd: '2026-05-08',
      minDate: '2026-05-20',
    }),
    '2026-05-20',
  );
});

test('date picker month navigation keeps focus on a valid enabled calendar day', () => {
  const resolveDatePickerMonthFocusYmd = (
    datePickerLogic as unknown as {
      resolveDatePickerMonthFocusYmd?: (options: {
        year: number;
        month: number;
        focusedYmd: string;
        minDate?: string;
      }) => string;
    }
  ).resolveDatePickerMonthFocusYmd;

  assert.equal(
    typeof resolveDatePickerMonthFocusYmd,
    'function',
    'DatePicker should clamp month-navigation focus to a valid enabled day.',
  );

  assert.equal(
    resolveDatePickerMonthFocusYmd({
      year: 2026,
      month: 5,
      focusedYmd: '2026-05-31',
    }),
    '2026-06-30',
  );
  assert.equal(
    resolveDatePickerMonthFocusYmd({
      year: 2026,
      month: 4,
      focusedYmd: '2026-05-08',
      minDate: '2026-05-20',
    }),
    '2026-05-20',
  );
  assert.equal(
    resolveDatePickerMonthFocusYmd({
      year: 2026,
      month: 5,
      focusedYmd: '2026-05-08',
      minDate: '2026-06-10',
    }),
    '2026-06-10',
  );
});
