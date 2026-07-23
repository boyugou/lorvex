import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

import { repoRoot } from "./shared.mjs";

const rootPath = path.join(
  repoRoot,
  "lorvex-store/tests/export_import_roundtrip.rs",
);
const moduleDir = path.join(
  repoRoot,
  "lorvex-store/tests/export_import_roundtrip",
);

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
  "full_roundtrip.rs": ["test_full_roundtrip"],
  "conflict_and_shadows.rs": [
    "test_payload_shadows_roundtrip_and_preserve_unknown_fields_in_export",
    "test_tombstones_survive_roundtrip",
    "test_version_conflict_keeps_newer",
  ],
  "audit_memory.rs": [
    "test_audit_entries_survive_roundtrip",
    "test_audit_export_filters_non_canonical_entries",
    "test_preferences_and_memory_roundtrip",
  ],
  "entity_domains.rs": [
    "test_calendar_events_roundtrip",
    "test_children_entities_roundtrip",
    "test_habit_completions_roundtrip",
  ],
  "empty_update_offline.rs": [
    "test_empty_db_roundtrip",
    "test_export_works_offline_empty_db",
    "test_import_updates_older_target_data",
  ],
  "focus_schedule.rs": ["test_focus_schedule_blocks_roundtrip"],
};

const expectedModuleNames = [
  "audit_memory",
  "conflict_and_shadows",
  "empty_update_offline",
  "entity_domains",
  "focus_schedule",
  "full_roundtrip",
  "support",
];

const forbiddenHeadingPhrasesByModule = {
  "audit_memory.rs": ["Habit completions"],
  "conflict_and_shadows.rs": ["Audit (ai_changelog)"],
  "empty_update_offline.rs": ["Focus schedule"],
  "entity_domains.rs": ["Empty export/import"],
  "focus_schedule.rs": ["offline export regression"],
  "full_roundtrip.rs": ["Version conflict"],
};

test("export import roundtrip integration tests are split by behavior domain", () => {
  const rootSource = readRoot();

  assert.ok(
    rootSource.split("\n").length <= 90,
    "export_import_roundtrip.rs should stay a small Cargo integration-test facade, not a 1200+ line hotspot",
  );
  assert.doesNotMatch(
    rootSource,
    /\nfn\s+setup_dirs\b/,
    "shared temp-dir helpers should live in export_import_roundtrip/support.rs",
  );
  assert.doesNotMatch(
    rootSource,
    /\n#\[test\]\n/,
    "behavior tests should live in export_import_roundtrip/*.rs modules",
  );

  const actualModuleDeclarations = [
    ...rootSource.matchAll(
      /^#\[path = "export_import_roundtrip\/([a-zA-Z0-9_]+)\.rs"\]\nmod \1;$/gm,
    ),
  ]
    .map((match) => match[1])
    .sort();
  assert.deepEqual(
    actualModuleDeclarations,
    expectedModuleNames.toSorted(),
    "export_import_roundtrip.rs should declare exactly the expected path-backed modules",
  );

  const actualModuleFiles = fs
    .readdirSync(moduleDir)
    .filter((entry) => entry.endsWith(".rs"))
    .sort();
  assert.deepEqual(
    actualModuleFiles,
    expectedModuleNames.map((moduleName) => `${moduleName}.rs`).sort(),
    "export_import_roundtrip directory should contain exactly the expected Rust module files",
  );

  assert.match(read("support.rs"), /\npub\(super\) struct TestDirs\b/);
  assert.match(read("support.rs"), /\npub\(super\) fn setup_dirs\b/);
  for (const fieldName of ["_dir", "zip_path"]) {
    assert.match(
      read("support.rs"),
      new RegExp(`\\n\\s+pub\\(super\\) ${fieldName}:`),
      `support.rs should expose TestDirs.${fieldName} to sibling test modules`,
    );
  }

  for (const moduleName of expectedModuleNames.filter(
    (name) => name !== "support",
  )) {
    assert.match(
      read(`${moduleName}.rs`),
      /^use super::support::\*;$/m,
      `${moduleName}.rs should import shared export/import test support`,
    );
  }

  assert.match(read("full_roundtrip.rs"), /\bfn\s+test_full_roundtrip\b/);
  assert.match(
    read("conflict_and_shadows.rs"),
    /\bfn\s+test_payload_shadows_roundtrip_and_preserve_unknown_fields_in_export\b/,
  );
  assert.match(
    read("audit_memory.rs"),
    /\bfn\s+test_audit_export_filters_non_canonical_entries\b/,
  );
  assert.match(
    read("entity_domains.rs"),
    /\bfn\s+test_calendar_events_roundtrip\b/,
  );
  assert.match(
    read("empty_update_offline.rs"),
    /\bfn\s+test_export_works_offline_empty_db\b/,
  );
  assert.match(
    read("focus_schedule.rs"),
    /\bfn\s+test_focus_schedule_blocks_roundtrip\b/,
  );

  for (const [relativePath, expectedNames] of Object.entries(
    expectedTestsByModule,
  )) {
    assert.deepEqual(
      testNamesIn(relativePath).sort(),
      expectedNames.toSorted(),
      `${relativePath} should own the expected export/import roundtrip test set`,
    );
  }

  for (const [relativePath, forbiddenPhrases] of Object.entries(
    forbiddenHeadingPhrasesByModule,
  )) {
    const source = read(relativePath);
    for (const phrase of forbiddenPhrases) {
      assert.doesNotMatch(
        source,
        new RegExp(phrase.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")),
        `${relativePath} should not keep stale section heading "${phrase}" from the pre-split hotspot`,
      );
    }
  }

  const actualTestNames = Object.keys(expectedTestsByModule)
    .flatMap(testNamesIn)
    .sort();
  const expectedTestNames = Object.values(expectedTestsByModule).flat().sort();
  assert.deepEqual(
    actualTestNames,
    expectedTestNames,
    "split export/import roundtrip modules should preserve the complete migrated test-name set",
  );
});
