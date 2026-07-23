import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, repoRoot } from './shared.mjs';

const ROOT = 'lorvex-store/src/calendar_timeline/recurrence.rs';

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('calendar recurrence runtime delegates helper domains to focused modules', () => {
  const rootSource = read(ROOT);
  const parseSource = read('lorvex-store/src/calendar_timeline/recurrence/parse.rs');
  const monthYearSource = read('lorvex-store/src/calendar_timeline/recurrence/month_year.rs');
  const weeklySource = read('lorvex-store/src/calendar_timeline/recurrence/weekly.rs');
  const occurrenceSource = read('lorvex-store/src/calendar_timeline/recurrence/occurrence.rs');
  const mutationSource = read('lorvex-store/src/calendar_timeline/recurrence/mutation.rs');
  const testsFacadeSource = read('lorvex-store/src/calendar_timeline/recurrence/tests.rs');
  const testsWeeklySource = read('lorvex-store/src/calendar_timeline/recurrence/tests/weekly.rs');

  for (const moduleName of ['month_year', 'mutation', 'occurrence', 'parse', 'weekly']) {
    assert.match(
      rootSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `recurrence.rs should register ${moduleName}.rs`,
    );
  }
  assert.match(rootSource, /^#\[cfg\(test\)\]\nmod tests;$/m);

  assert.ok(
    hasRustUseReexport(rootSource, {
      modulePath: 'month_year',
      symbols: ['add_months_clamped'],
    }),
    'root should preserve public month arithmetic helpers through re-export',
  );
  assert.ok(
    hasRustUseReexport(rootSource, {
      modulePath: 'occurrence',
      symbols: [
        'calculate_next_occurrence_date',
        'count_end_date',
        'first_occurrence_on_or_after',
        'next_occurrence_strictly_after',
        'overlaps_calendar_range',
        'recurs_on_date',
      ],
    }),
    'root should preserve public occurrence helpers through re-export',
  );
  assert.ok(
    hasRustUseReexport(rootSource, {
      modulePath: 'parse',
      symbols: ['MAX_RECURRENCE_COUNT', 'parse_ymd'],
    }),
    'root should preserve public parsing helpers through re-export',
  );
  assert.ok(
    hasRustUseReexport(rootSource, {
      modulePath: 'weekly',
      symbols: ['first_weekly_byday_occurrence_on_or_after', 'weekly_target_dows'],
    }),
    'root should preserve weekly helpers through re-export',
  );
  assert.ok(
    hasRustUseReexport(rootSource, {
      modulePath: 'mutation',
      symbols: ['decrement_recurrence_count', 'inject_bymonthday'],
    }),
    'root should preserve recurrence mutation helpers through re-export',
  );
  assert.ok(
    rootSource.split('\n').length <= 90,
    'recurrence.rs should stay a small composition boundary',
  );
  assert.doesNotMatch(
    rootSource,
    /\nfn parse_rule_object\b|\nfn parse_freq\b|\nfn parse_interval\b|\nfn parse_bymonthday\b|\nfn parse_byday_token\b|\nfn month_candidates\b|\nfn first_monthly_candidate_on_or_after\b|\nfn yearly_candidates\b|\nfn first_weekly_candidate_on_or_after\b|\npub fn first_occurrence_on_or_after\b|\npub fn recurs_on_date\b|\npub fn inject_bymonthday\b|\npub fn decrement_recurrence_count\b/,
    'recurrence.rs should not keep extracted helper implementations inline',
  );

  assert.match(parseSource, /\npub\(crate\) enum ByMonthDayAnchor\b/);
  assert.match(parseSource, /\npub\(super\) fn parse_rule_object\b/);
  assert.match(parseSource, /\npub\(super\) fn parse_bymonth\b/);
  assert.match(parseSource, /\npub\(super\) fn parse_bysetpos\b/);
  assert.match(parseSource, /\npub\(super\) fn parse_wkst\b/);
  assert.match(monthYearSource, /\npub\(crate\) fn add_months_with_anchor\b/);
  assert.match(monthYearSource, /\npub\(super\) fn month_candidates\b/);
  assert.match(monthYearSource, /\npub\(super\) fn first_yearly_candidate_on_or_after\b/);
  assert.match(weeklySource, /\npub fn weekly_target_dows\b/);
  assert.match(weeklySource, /\npub\(super\) fn first_weekly_candidate_on_or_after\b/);
  assert.match(occurrenceSource, /\npub fn first_occurrence_on_or_after\b/);
  assert.match(occurrenceSource, /\npub fn count_end_date\b/);
  assert.match(mutationSource, /\npub fn inject_bymonthday\b/);
  assert.match(mutationSource, /\npub fn decrement_recurrence_count\b/);
  assert.match(testsFacadeSource, /^mod weekly;$/m);
  assert.match(testsWeeklySource, /\bfn\s+byday_occurrence_next_interval\b/);
});
