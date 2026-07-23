import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

import { repoRoot } from "./shared.mjs";

const legacyPath = path.join(repoRoot, "lorvex-domain/src/validation/tests.rs");
const moduleDir = path.join(repoRoot, "lorvex-domain/src/validation/tests");

function read(relativePath) {
  return fs.readFileSync(path.join(moduleDir, relativePath), "utf8");
}

function testNamesIn(relativePath) {
  return [
    ...read(relativePath).matchAll(
      /^#\[test\]\n(?:#\[[^\n]+\]\n)*fn\s+([a-zA-Z0-9_]+)\s*\(/gm,
    ),
  ].map((match) => match[1]);
}

const expectedTestsByModule = {
  "text.rs": [
    "body_at_max_length",
    "body_at_max_length_of_multi_byte_codepoints_passes",
    "body_empty_is_ok",
    "body_over_max_codepoints_rejected",
    "body_too_long",
    "body_valid",
    "body_visually_empty_rejects",
    "body_zws_padded_repeat_rejects",
    "tag_name_at_max",
    "tag_name_empty",
    "tag_name_too_long",
    "tag_name_unicode",
    "tag_name_valid",
    "tag_name_visually_empty_rejects",
    "tag_name_whitespace_only",
    "title_at_max_length",
    "title_at_max_length_of_multi_byte_codepoints_passes",
    "title_empty",
    "title_pure_invisible_rejects",
    "title_too_long",
    "title_unicode_valid",
    "title_valid",
    "title_whitespace_only",
    "title_zws_padded_x_rejects",
  ],
  "numeric.rs": [
    "estimated_minutes_max",
    "estimated_minutes_negative",
    "estimated_minutes_one_is_minimum",
    "estimated_minutes_over_max",
    "estimated_minutes_valid",
    "estimated_minutes_zero_is_rejected",
    "mood_too_high",
    "mood_too_low",
    "mood_valid_range",
    "priority_negative",
    "priority_too_high",
    "priority_too_low",
    "priority_valid_range",
    "reminder_window_max",
    "reminder_window_negative",
    "reminder_window_over_max",
    "reminder_window_valid",
    "reminder_window_zero",
  ],
  "format.rs": [
    "calendar_url_rejects_javascript_with_leading_zero_width",
    "date_day_32",
    "date_empty",
    "date_garbage",
    "date_leap_day_invalid",
    "date_leap_day_valid",
    "date_month_13",
    "date_valid",
    "date_wrong_format_day_month",
    "date_wrong_format_slash",
    "time_empty",
    "time_end_of_day",
    "time_hour_24",
    "time_letters",
    "time_midnight",
    "time_minute_60",
    "time_single_digit_hour",
    "time_valid",
    "time_wrong_format_no_colon",
    "time_wrong_format_seconds",
    "url_allows_http",
    "url_allows_https",
    "url_allows_mailto",
    "url_allows_tel",
    "url_lowercases_scheme_in_canonical_form",
    "url_rejects_control_characters",
    "url_rejects_data_scheme",
    "url_rejects_empty",
    "url_rejects_file_scheme",
    "url_rejects_javascript_scheme",
    "url_rejects_javascript_scheme_case_insensitive",
    "url_rejects_javascript_scheme_with_leading_zero_width",
    "url_rejects_no_scheme",
    "url_rejects_whitespace_only",
    "url_strips_leading_zero_width_for_legitimate_scheme",
    "url_validators_return_sanitized_canonical_form_for_bidi_zero_width",
  ],
  "errors_sql.rs": [
    "display_empty",
    "display_invalid_format",
    "display_out_of_range",
    "display_too_long",
    "sql_identifier_rejects_dash",
    "sql_identifier_rejects_empty",
    "sql_identifier_rejects_parens",
    "sql_identifier_rejects_quotes",
    "sql_identifier_rejects_semicolon",
    "sql_identifier_rejects_spaces",
    "sql_identifier_valid_simple",
    "sql_identifier_valid_with_digits",
    "sql_identifier_valid_with_underscores",
  ],
  "recurrence_core.rs": [
    "recurrence_bymonthday_array_rejects_out_of_range_entry",
    "recurrence_bymonthday_array_sorts_and_dedupes",
    "recurrence_bymonthday_empty_array_drops_the_key",
    "recurrence_bymonthday_only_valid_for_monthly_yearly",
    "recurrence_bymonthday_valid_for_monthly",
    "recurrence_bymonthday_valid_for_yearly",
    "recurrence_byday_only_valid_for_weekly",
    "recurrence_canonical_key_order_preserved",
    "recurrence_count_and_until_mutually_exclusive",
    "recurrence_count_valid",
    "recurrence_empty_input_returns_none",
    "recurrence_invalid_freq_rejected",
    "recurrence_negative_interval_rejected",
    "recurrence_unknown_key_rejected",
    "recurrence_until_accepts_rfc5545_date",
    "recurrence_until_accepts_rfc5545_date_time",
    "recurrence_until_rejects_garbage",
    "recurrence_until_valid",
    "recurrence_valid_daily_normalized",
    "recurrence_zero_count_rejected",
  ],
  "recurrence_byday.rs": [
    "byday_token_accepts_bare_codes_for_every_freq",
    "byday_token_monthly_caps_ordinal_at_five",
    "byday_token_rejects_garbage_and_out_of_range",
    "byday_token_weekly_rejects_every_ordinal",
    "byday_token_yearly_accepts_full_ordinal_range",
    "recurrence_bysetpos_array_accepted",
    "recurrence_bysetpos_rejected_for_daily_and_weekly",
    "recurrence_bysetpos_rejects_zero_and_out_of_range",
    "recurrence_monthly_byday_with_ordinal_accepted",
    "recurrence_monthly_rejects_byday_ordinal_above_five",
    "recurrence_weekly_rejects_byday_ordinal_prefix",
    "recurrence_wkst_accepted_and_canonicalized",
    "recurrence_wkst_rejects_invalid_code",
    "recurrence_yearly_accepts_byday_ordinal_at_full_range",
    "recurrence_yearly_byday_with_negative_ordinal_accepted",
  ],
  "recurrence_bymonth_warnings.rs": [
    "recurrence_by_arrays_canonicalized_sort_dedup",
    "recurrence_byhour_byminute_rejected_until_time_expansion_is_supported",
    "recurrence_byhour_rejects_out_of_range",
    "recurrence_byminute_rejects_out_of_range",
    "recurrence_bymonth_rejects_zero_and_thirteen",
    "recurrence_bymonthday_28_does_not_warn",
    "recurrence_bymonthday_29_30_31_emit_warning",
    "recurrence_bymonthday_31_emits_skip_warning",
    "recurrence_bymonthday_31_on_yearly_also_warns",
    "recurrence_bymonthday_negative_does_not_warn",
    "recurrence_daily_rejects_bymonth",
    "recurrence_leap_year_birthday_accepted_with_dedicated_warning",
    "recurrence_weekly_bymonth_accepted",
    "recurrence_yearly_bymonth_accepted_and_canonicalized",
  ],
};

const expectedModuleNames = [
  "errors_sql",
  "format",
  "numeric",
  "recurrence_byday",
  "recurrence_bymonth_warnings",
  "recurrence_core",
  "text",
];

test("lorvex-domain validation unit tests are split by validator domain", () => {
  assert.ok(
    !fs.existsSync(legacyPath),
    "validation unit tests should use tests/mod.rs, not the old 1300+ line tests.rs hotspot",
  );

  const rootSource = read("mod.rs");
  assert.ok(
    rootSource.split("\n").length <= 80,
    "validation/tests/mod.rs should stay a small test facade",
  );

  const actualModuleDeclarations = [
    ...rootSource.matchAll(/^mod ([a-zA-Z0-9_]+);$/gm),
  ]
    .map((match) => match[1])
    .sort();
  assert.deepEqual(
    actualModuleDeclarations,
    expectedModuleNames.toSorted(),
    "validation/tests/mod.rs should declare exactly the expected test modules",
  );

  const actualModuleFiles = fs
    .readdirSync(moduleDir)
    .filter((entry) => entry.endsWith(".rs"))
    .sort();
  assert.deepEqual(
    actualModuleFiles,
    [
      "mod.rs",
      ...expectedModuleNames.map((moduleName) => `${moduleName}.rs`),
    ].sort(),
    "validation/tests should contain exactly the expected Rust module files",
  );

  for (const moduleName of expectedModuleNames) {
    assert.match(
      rootSource,
      new RegExp(`^mod ${moduleName};$`, "m"),
      `validation/tests/mod.rs should register ${moduleName}.rs`,
    );
    assert.ok(
      fs.existsSync(path.join(moduleDir, `${moduleName}.rs`)),
      `${moduleName}.rs should exist under lorvex-domain/src/validation/tests/`,
    );
    assert.match(
      read(`${moduleName}.rs`),
      /^use super::super::\*;$/m,
      `${moduleName}.rs should import validation symbols from the parent module`,
    );
  }

  assert.match(read("text.rs"), /\bfn\s+title_pure_invisible_rejects\b/);
  assert.match(
    read("format.rs"),
    /\bfn\s+url_lowercases_scheme_in_canonical_form\b/,
  );
  assert.match(
    read("numeric.rs"),
    /\bfn\s+estimated_minutes_zero_is_rejected\b/,
  );
  assert.match(
    read("errors_sql.rs"),
    /\bfn\s+sql_identifier_rejects_semicolon\b/,
  );
  assert.match(
    read("recurrence_core.rs"),
    /\bfn\s+recurrence_until_accepts_rfc5545_date_time\b/,
  );
  assert.match(
    read("recurrence_byday.rs"),
    /\bfn\s+recurrence_bysetpos_array_accepted\b/,
  );
  assert.match(
    read("recurrence_bymonth_warnings.rs"),
    /\bfn\s+recurrence_bymonthday_31_emits_skip_warning\b/,
  );

  for (const [relativePath, expectedNames] of Object.entries(
    expectedTestsByModule,
  )) {
    assert.deepEqual(
      testNamesIn(relativePath).sort(),
      expectedNames.toSorted(),
      `${relativePath} should own the expected validation test set`,
    );
  }

  const actualTestNames = Object.keys(expectedTestsByModule)
    .flatMap(testNamesIn)
    .sort();
  const expectedTestNames = Object.values(expectedTestsByModule).flat().sort();
  assert.deepEqual(
    actualTestNames,
    expectedTestNames,
    "split validation test modules should preserve the complete migrated test-name set",
  );
});
