import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

import { repoRoot } from "./shared.mjs";

const legacyPath = path.join(
  repoRoot,
  "lorvex-store/src/import/tests/apply_entities.rs",
);
const moduleDir = path.join(
  repoRoot,
  "lorvex-store/src/import/tests/apply_entities",
);
const rootPath = path.join(moduleDir, "mod.rs");

const expectedModules = [
  "domain_validation",
  "list_tag_validation",
  "support",
  "task_defer_reason",
  "task_required_refs",
  "task_scrubbing",
  "task_text_limits",
  "task_value_validation",
  "versioning",
];

const modulesUsingTaskImportZipSupport = [
  "task_defer_reason",
  "task_scrubbing",
  "task_text_limits",
  "task_value_validation",
];

const expectedTestsByModule = {
  "domain_validation.rs": [
    "import_preserves_calendar_event_override_linkage_fields",
    "import_rejects_all_day_calendar_event_with_times_before_db_insert",
    "import_rejects_habit_with_invalid_color_before_db_insert",
    "import_rejects_invalid_canonical_calendar_event_type_before_db_insert",
    "import_rejects_legacy_underscore_attendee_status_before_db_insert",
    "import_rejects_malformed_calendar_event_boundary_fields_before_db_insert",
    "import_rejects_malformed_calendar_event_override_linkage_before_db_insert",
  ],
  "list_tag_validation.rs": [
    "import_rejects_list_missing_name",
    "import_rejects_list_with_oversized_name",
    "import_rejects_tag_missing_created_at",
    "import_rejects_tag_payload_missing_lookup_key",
  ],
  "task_defer_reason.rs": [
    "import_rejects_task_with_invalid_last_defer_reason",
    "import_sanitizes_task_last_defer_reason_before_validation",
    "import_treats_empty_task_last_defer_reason_as_clear",
    "import_treats_sanitized_empty_task_last_defer_reason_as_clear",
  ],
  "task_required_refs.rs": [
    "import_rejects_task_missing_defer_count",
    "import_rejects_task_missing_status",
    "import_rejects_task_with_missing_list_reference",
    "import_rejects_task_with_null_list_id",
  ],
  "task_scrubbing.rs": [
    "import_scrubs_embedded_task_checklist_item_text_before_storage",
    "import_scrubs_standalone_task_checklist_item_text_before_storage",
    "import_scrubs_task_text_fields_before_storage",
  ],
  "task_text_limits.rs": [
    "import_rejects_task_with_oversized_ai_notes",
    "import_rejects_task_with_oversized_raw_input",
    "import_rejects_task_with_oversized_title",
  ],
  "task_value_validation.rs": [
    "import_rejects_task_non_integer_priority_when_present",
    "import_rejects_task_with_malformed_due_date",
    "import_rejects_task_with_negative_defer_count",
    "import_rejects_task_with_negative_estimated_minutes",
    "import_rejects_task_with_unknown_status",
  ],
  "versioning.rs": [
    "import_list_explicit_null_archive_clears_without_resetting_absent_position",
    "import_older_list_payload_preserves_missing_archive_and_position_fields",
    "import_rejects_entity_with_non_hlc_version",
    "import_rejects_existing_entity_with_non_hlc_local_version",
    "import_rejects_missing_entity_version",
    "import_restores_list_archive_and_position_fields",
    "import_skips_newer_existing_entities",
  ],
};

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

test("lorvex-store import apply entity tests are split by validation domain", () => {
  assert.equal(
    fs.existsSync(legacyPath),
    false,
    "import/tests/apply_entities.rs should not remain as a 1000+ line hotspot",
  );
  assert.equal(
    fs.existsSync(rootPath),
    true,
    "import/tests/apply_entities/mod.rs should exist",
  );

  const rootSource = fs.readFileSync(rootPath, "utf8");
  assert.ok(
    rootSource.split("\n").length <= 80,
    "apply_entities/mod.rs should stay a small test-module facade",
  );
  assert.doesNotMatch(
    rootSource,
    /\n#\[test\]\n/,
    "behavior tests should live in apply_entities/*.rs modules",
  );
  assert.doesNotMatch(
    rootSource,
    /\nfn\s+write_task_import_zip\b/,
    "shared task import ZIP helper should live in support.rs",
  );

  const actualModuleDeclarations = [
    ...rootSource.matchAll(/^mod ([a-z_]+);$/gm),
  ]
    .map((match) => match[1])
    .sort();
  assert.deepEqual(
    actualModuleDeclarations,
    expectedModules.toSorted(),
    "apply_entities/mod.rs should declare exactly the expected behavior modules",
  );

  const actualFiles = fs
    .readdirSync(moduleDir)
    .filter((entry) => entry.endsWith(".rs"))
    .sort();
  assert.deepEqual(
    actualFiles,
    [
      "mod.rs",
      ...expectedModules.map((moduleName) => `${moduleName}.rs`),
    ].sort(),
    "apply_entities directory should contain exactly the expected Rust module files",
  );

  const supportSource = read("support.rs");
  assert.match(
    supportSource,
    /\npub\(super\) fn write_task_import_zip\b/,
    "support.rs should own the shared task import ZIP helper",
  );

  for (const moduleName of expectedModules.filter(
    (name) => name !== "support",
  )) {
    const source = read(`${moduleName}.rs`);
    assert.match(
      source,
      /^use super::super::\*;$/m,
      `${moduleName}.rs should import shared import test support`,
    );
    if (modulesUsingTaskImportZipSupport.includes(moduleName)) {
      assert.match(
        source,
        /^use super::support::\*;$/m,
        `${moduleName}.rs should import apply-entity helper support`,
      );
    } else {
      assert.doesNotMatch(
        source,
        /^use super::support::\*;$/m,
        `${moduleName}.rs should avoid unused apply-entity helper imports`,
      );
    }
  }

  for (const [relativePath, expectedNames] of Object.entries(
    expectedTestsByModule,
  )) {
    assert.deepEqual(
      testNamesIn(relativePath).sort(),
      expectedNames.toSorted(),
      `${relativePath} should own the expected import apply entity test set`,
    );
  }

  const actualTestNames = Object.keys(expectedTestsByModule)
    .flatMap(testNamesIn)
    .sort();
  const expectedTestNames = Object.values(expectedTestsByModule).flat().sort();
  assert.deepEqual(
    actualTestNames,
    expectedTestNames,
    "split import apply entity modules should preserve the complete migrated test-name set",
  );
});
