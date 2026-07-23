import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const facadePath = path.join(repoRoot, 'lorvex-store/src/calendar_timeline/recurrence/tests.rs');
const recurrenceTestsDir = path.join(repoRoot, 'lorvex-store/src/calendar_timeline/recurrence/tests');

function read(relativePath) {
  return fs.readFileSync(path.join(recurrenceTestsDir, relativePath), 'utf8');
}

function testNames(source) {
  return [...source.matchAll(/\n#\[test\]\s*\nfn\s+([a-zA-Z0-9_]+)\s*\(/g)].map((match) => match[1]);
}

function assertOwnsTests(source, expectedNames, label) {
  const names = testNames(source);
  assert.deepEqual(
    names.filter((name) => expectedNames.includes(name)).sort(),
    expectedNames.toSorted(),
    `${label} should own its expected test functions`,
  );
  assert.equal(new Set(names).size, names.length, `${label} test names should stay unique`);
}

test('calendar recurrence tests stay split by recurrence responsibility', () => {
  const facadeSource = fs.readFileSync(facadePath, 'utf8');
  assert.ok(
    fs.existsSync(recurrenceTestsDir),
    'calendar_timeline/recurrence/tests/ should contain extracted recurrence test modules',
  );

  const moduleFiles = fs
    .readdirSync(recurrenceTestsDir)
    .filter((fileName) => fileName.endsWith('.rs'))
    .sort();
  assert.deepEqual(moduleFiles, [
    'count_end.rs',
    'date_math.rs',
    'first_occurrence.rs',
    'helpers.rs',
    'next_occurrence.rs',
    'recurs_on_date.rs',
    'validation.rs',
    'weekly.rs',
  ]);

  for (const moduleName of [
    'count_end',
    'date_math',
    'first_occurrence',
    'helpers',
    'next_occurrence',
    'recurs_on_date',
    'validation',
    'weekly',
  ]) {
    assert.match(
      facadeSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `tests.rs should register ${moduleName}.rs`,
    );
  }

  const facadeLineCount = facadeSource.trimEnd().split('\n').length;
  assert.ok(facadeLineCount <= 14, `tests.rs should stay a thin facade, got ${facadeLineCount} lines`);
  assert.doesNotMatch(
    facadeSource,
    /\n#\[test\]|\nfn\s+\w+|\nstruct\s+\w+|\nimpl\s+/,
    'tests.rs should not keep tests or helpers inline',
  );

  assertOwnsTests(read('validation.rs'), [
    'decrement_recurrence_count_accepts_uncapped_positive_count',
    'first_occurrence_rejects_malformed_rule_json',
    'inject_bymonthday_rejects_invalid_due_date',
    'inject_bymonthday_skips_positional_rules',
    'next_occurrence_rejects_invalid_until_date',
    'parse_ymd_invalid_returns_validation_error',
    'parse_ymd_valid',
  ], 'validation.rs');

  assertOwnsTests(read('date_math.rs'), [
    'add_months_clamped_basic',
    'add_months_clamped_feb_clamp',
    'add_months_clamped_target_day_anchor',
    'overlaps_range_entirely_before',
    'overlaps_range_identical',
    'overlaps_range_no_overlap',
    'overlaps_range_single_day_boundary',
  ], 'date_math.rs');

  assertOwnsTests(read('recurs_on_date.rs'), [
    'recurs_on_date_base_is_match',
    'recurs_on_date_before_base',
    'recurs_on_date_count_daily',
    'recurs_on_date_daily',
    'recurs_on_date_monthly',
    'recurs_on_date_monthly_byday_bysetpos_matches_first_monday',
    'recurs_on_date_rejects_excessive_count_for_expansion_budget',
    'recurs_on_date_rejects_invalid_count_zero',
    'recurs_on_date_until_exceeded',
    'recurs_on_date_weekly',
    'recurs_on_date_yearly',
    'recurs_on_date_yearly_bymonth_bymonthday_only_matches_leap_day',
  ], 'recurs_on_date.rs');

  assertOwnsTests(read('first_occurrence.rs'), [
    'first_occurrence_daily_before_base',
    'first_occurrence_daily_with_interval',
    'first_occurrence_monthly_byday_bysetpos_picks_first_monday',
    'first_occurrence_monthly_bymonthday_skips_short_month',
    'first_occurrence_until_exceeded',
    'first_occurrence_weekly_byday_order_respects_wkst',
    'first_occurrence_weekly_bymonth_filters_out_other_months',
    'first_occurrence_weekly_interval_respects_wkst',
    'first_occurrence_weekly_no_byday',
    'first_occurrence_weekly_with_byday',
    'first_occurrence_yearly_bymonth_bymonthday_skips_to_leap_day',
    'first_occurrence_yearly_bymonth_without_bymonthday_uses_base_day_in_target_month',
    'first_occurrence_yearly_clamps_leap_day',
    'first_occurrence_yearly_ordinal_byday_scans_whole_year',
    'first_occurrence_yearly_preserves_leap_day',
  ], 'first_occurrence.rs');

  assertOwnsTests(read('next_occurrence.rs'), [
    'monthly_bymonthday_negative_one_resolves_to_last_day_of_month',
    'monthly_bymonthday_negative_two_resolves_to_penultimate_day',
    'monthly_bymonthday_rejects_zero_and_out_of_range_values',
    'next_occurrence_daily_basic',
    'next_occurrence_monthly_ordinal_byday_picks_first_monday',
    'next_occurrence_weekly_basic',
    'next_occurrence_weekly_byday_order_respects_wkst',
    'next_occurrence_weekly_bymonth_filters_out_other_months',
    'next_occurrence_weekly_interval_respects_wkst',
    'next_occurrence_yearly_byday_bysetpos_scans_whole_year',
    'next_occurrence_yearly_bymonth_bymonthday_skips_non_leap_years',
    'next_occurrence_yearly_bymonth_without_bymonthday_uses_base_day_in_target_month',
    'strictly_after_base_wins',
    'strictly_after_today_wins',
    'until_date_prevents_next_occurrence',
    'yearly_recurrence_clamps_leap_day_to_feb_28',
    'yearly_recurrence_normal_date',
    'yearly_recurrence_preserves_leap_day_in_leap_year',
  ], 'next_occurrence.rs');

  assertOwnsTests(read('count_end.rs'), [
    'count_end_accepts_count_at_cap',
    'count_end_count_1_returns_base',
    'count_end_daily_count_3',
    'count_end_monthly_byday_bysetpos_counts_first_mondays',
    'count_end_no_count_returns_none',
    'count_end_rejects_excessive_count',
    'count_end_weekly_count_2',
    'count_end_yearly_bymonth_bymonthday_counts_leap_day_occurrences',
    'count_end_yearly_from_leap_day_clamps',
  ], 'count_end.rs');

  assertOwnsTests(read('weekly.rs'), [
    'byday_occurrence_next_interval',
    'byday_occurrence_same_week',
    'weekly_target_dows_absent_returns_none',
    'weekly_target_dows_empty_returns_none',
    'weekly_target_dows_returns_sorted',
  ], 'weekly.rs');
});
