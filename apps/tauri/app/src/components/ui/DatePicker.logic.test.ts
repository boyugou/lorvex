import { describe, expect, it } from 'vitest';

import {
  buildDatePickerGrid,
  getDatePickerWeekdayKeys,
  resolveDatePickerArrowFocusYmd,
  resolveDatePickerInitialFocusYmd,
} from './DatePicker.logic';

describe('DatePicker week-start layout', () => {
  it('orders weekday headers from the configured Sunday start', () => {
    expect(getDatePickerWeekdayKeys(0)).toEqual([
      'calendar.weekday.su',
      'calendar.weekday.mo',
      'calendar.weekday.tu',
      'calendar.weekday.we',
      'calendar.weekday.th',
      'calendar.weekday.fr',
      'calendar.weekday.sa',
    ]);
  });

  it('orders weekday headers from the configured Monday start', () => {
    expect(getDatePickerWeekdayKeys(1)).toEqual([
      'calendar.weekday.mo',
      'calendar.weekday.tu',
      'calendar.weekday.we',
      'calendar.weekday.th',
      'calendar.weekday.fr',
      'calendar.weekday.sa',
      'calendar.weekday.su',
    ]);
  });

  it('orders weekday headers from the configured Saturday start', () => {
    expect(getDatePickerWeekdayKeys(6)).toEqual([
      'calendar.weekday.sa',
      'calendar.weekday.su',
      'calendar.weekday.mo',
      'calendar.weekday.tu',
      'calendar.weekday.we',
      'calendar.weekday.th',
      'calendar.weekday.fr',
    ]);
  });

  it('offsets month cells against Sunday, Monday, and Saturday week starts', () => {
    expect(buildDatePickerGrid(2026, 4, 0).slice(0, 7).map((cell) => cell?.day ?? null)).toEqual([
      null,
      null,
      null,
      null,
      null,
      1,
      2,
    ]);
    expect(buildDatePickerGrid(2026, 4, 1).slice(0, 7).map((cell) => cell?.day ?? null)).toEqual([
      null,
      null,
      null,
      null,
      1,
      2,
      3,
    ]);
    expect(buildDatePickerGrid(2026, 4, 6).slice(0, 7).map((cell) => cell?.day ?? null)).toEqual([
      null,
      null,
      null,
      null,
      null,
      null,
      1,
    ]);
  });

  it('moves keyboard focus by arrow key while preserving calendar date semantics', () => {
    expect(resolveDatePickerArrowFocusYmd({
      focusedYmd: '2026-05-15',
      key: 'ArrowLeft',
    })).toBe('2026-05-14');
    expect(resolveDatePickerArrowFocusYmd({
      focusedYmd: '2026-05-15',
      key: 'ArrowRight',
    })).toBe('2026-05-16');
    expect(resolveDatePickerArrowFocusYmd({
      focusedYmd: '2026-05-15',
      key: 'ArrowUp',
    })).toBe('2026-05-08');
    expect(resolveDatePickerArrowFocusYmd({
      focusedYmd: '2026-05-15',
      key: 'ArrowDown',
    })).toBe('2026-05-22');
  });

  it('does not move keyboard focus onto disabled dates before minDate', () => {
    expect(resolveDatePickerArrowFocusYmd({
      focusedYmd: '2026-05-10',
      key: 'ArrowUp',
      minDate: '2026-05-10',
    })).toBe('2026-05-10');
  });

  it('initializes no-selected-value keyboard focus from the first enabled candidate', () => {
    expect(resolveDatePickerInitialFocusYmd({
      value: null,
      todayYmd: '2026-05-01',
      minDate: '2026-05-10',
    })).toBe('2026-05-10');
  });
});
