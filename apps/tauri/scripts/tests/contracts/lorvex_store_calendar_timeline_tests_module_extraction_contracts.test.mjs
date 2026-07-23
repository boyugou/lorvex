import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

import { repoRoot } from "./shared.mjs";

const rootPath = path.join(repoRoot, "lorvex-store/tests/calendar_timeline.rs");
const moduleDir = path.join(repoRoot, "lorvex-store/tests/calendar_timeline");

function readRoot() {
  return fs.readFileSync(rootPath, "utf8");
}

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
  "access_modes.rs": [
    "blocking_ranges_busy_only_redacts_provider_title",
    "blocking_ranges_off_excludes_provider",
    "timeline_busy_only_redacts_provider_details",
    "timeline_off_excludes_provider_entirely",
  ],
  "blocking_ranges.rs": [
    "blocking_ranges_canonical_event_id_set_for_canonical_only",
    "blocking_ranges_default_end_time_when_missing",
    "blocking_ranges_includes_provider_events",
    "blocking_ranges_multi_day_event_does_not_double_count",
    "blocking_ranges_reject_malformed_recurrence_rule_json",
    "blocking_ranges_respects_recurrence_exceptions",
    "blocking_ranges_skips_all_day_events",
  ],
  "recurrence_pruning.rs": [
    "recurrence_end_date_generated_column_mirrors_until_on_insert_and_update",
    "recurrence_end_date_generated_column_normalizes_rfc5545_basic_format",
    "timeline_prunes_provider_recurring_event_whose_until_has_passed",
    "timeline_prunes_recurring_event_whose_until_has_passed",
  ],
  "timeline_queries.rs": [
    "search_calendar_events_returns_matching_canonical_rows_from_fts_rowids",
    "timeline_excludes_provider_scope_before_first_successful_refresh",
    "timeline_excludes_provider_when_not_requested",
    "timeline_expands_leap_day_yearly_recurrence_without_feb_28_shadow",
    "timeline_expands_monthly_byday_bysetpos_recurrence",
    "timeline_expands_recurring_canonical_event",
    "timeline_expands_recurring_provider_event",
    "timeline_includes_both_canonical_and_provider_events",
    "timeline_rejects_malformed_recurrence_rule_json",
    "timeline_with_empty_provider_table_returns_only_canonical",
  ],
  "timezone_resilience.rs": [
    "blocking_ranges_project_provider_tzid_occurrence_into_anchor_day",
    "timeline_projects_canonical_explicit_timezone_into_anchor_day",
    "timeline_projects_provider_tzid_occurrence_into_anchor_day",
    "timeline_skips_event_with_invalid_anchor_timezone",
    "timeline_skips_event_with_invalid_source_timezone",
    "timeline_skips_event_with_invalid_start_time",
  ],
};

test("calendar timeline integration tests are split into focused modules", () => {
  const rootSource = readRoot();

  assert.ok(
    rootSource.split("\n").length <= 80,
    "calendar_timeline.rs should stay a small Cargo integration-test facade, not a 1400+ line hotspot",
  );
  assert.doesNotMatch(
    rootSource,
    /\nfn\s+insert_canonical_event\b/,
    "shared seed helpers should live in calendar_timeline/support.rs",
  );
  assert.doesNotMatch(
    rootSource,
    /\n#\[test\]\n/,
    "behavior tests should live in calendar_timeline/*.rs modules",
  );

  for (const moduleName of [
    "access_modes",
    "blocking_ranges",
    "recurrence_pruning",
    "support",
    "timeline_queries",
    "timezone_resilience",
  ]) {
    assert.match(
      rootSource,
      new RegExp(
        `^#\\[path = "calendar_timeline/${moduleName}\\.rs"\\]\\nmod ${moduleName};$`,
        "m",
      ),
      `calendar_timeline.rs should register ${moduleName}.rs through an explicit integration-test path`,
    );
    assert.ok(
      fs.existsSync(path.join(moduleDir, `${moduleName}.rs`)),
      `${moduleName}.rs should exist under lorvex-store/tests/calendar_timeline/`,
    );
  }

  assert.match(
    read("support.rs"),
    /\npub\(super\) fn insert_canonical_event\b/,
  );
  assert.match(read("support.rs"), /\npub\(super\) fn insert_provider_event\b/);
  assert.match(
    read("timeline_queries.rs"),
    /\bfn\s+timeline_includes_both_canonical_and_provider_events\b/,
  );
  assert.match(
    read("blocking_ranges.rs"),
    /\bfn\s+blocking_ranges_respects_recurrence_exceptions\b/,
  );
  assert.match(
    read("access_modes.rs"),
    /\bfn\s+timeline_busy_only_redacts_provider_details\b/,
  );
  assert.match(
    read("timezone_resilience.rs"),
    /\bfn\s+timeline_skips_event_with_invalid_start_time\b/,
  );
  assert.match(
    read("recurrence_pruning.rs"),
    /\bfn\s+recurrence_end_date_generated_column_normalizes_rfc5545_basic_format\b/,
  );

  for (const [relativePath, expectedNames] of Object.entries(
    expectedTestsByModule,
  )) {
    assert.deepEqual(
      testNamesIn(relativePath).sort(),
      expectedNames.toSorted(),
      `${relativePath} should own the expected calendar timeline test set`,
    );
  }

  const actualTestNames = Object.keys(expectedTestsByModule)
    .flatMap(testNamesIn)
    .sort();
  const expectedTestNames = Object.values(expectedTestsByModule).flat().sort();
  assert.deepEqual(
    actualTestNames,
    expectedTestNames,
    "split calendar timeline modules should preserve the complete test-name set",
  );
});
