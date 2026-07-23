import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot, rustModuleDeclarationPattern } from './shared.mjs';

// Calendar subscription tests are split across two canonical homes
// after the ICS-parsing lift (#3066): the workflow tree owns the
// pure parse/recurrence/tzid/validation behaviors, and the Tauri
// tree retains the IPC/HTTP/DB-orchestration behaviors that still
// live in the Tauri surface (fetch, body-cap, mutations,
// source-contract typing, end-to-end sync glue).
test('calendar subscription sync tests are organized as focused modules instead of one hotspot file', () => {
  const tauriLegacy = path.join(
    repoRoot,
    'app/src-tauri/src/calendar_subscription_sync/tests.rs',
  );
  const tauriDir = path.join(repoRoot, 'app/src-tauri/src/calendar_subscription_sync/tests');
  const workflowDir = path.join(repoRoot, 'lorvex-workflow/src/calendar_subscription/tests');

  assert.equal(
    fs.existsSync(tauriLegacy),
    false,
    'calendar_subscription_sync/tests.rs should stay replaced by a tests/ module tree',
  );

  const expectedTauriModules = [
    'fetch',
    'fetch_body',
    'mutations',
    'source_contract',
    'sync',
  ];
  const expectedWorkflowModules = [
    'parse_core',
    'parse_properties',
    'parse_recurrence',
    'parse_truncation',
    'parse_vtimezone',
    'scheduling',
    'sync',
    'tzid',
    'validation',
    'vtimezone',
  ];

  const tauriMod = fs.readFileSync(path.join(tauriDir, 'mod.rs'), 'utf8');
  for (const moduleName of expectedTauriModules) {
    assert.match(
      tauriMod,
      rustModuleDeclarationPattern(moduleName),
      `Tauri tests/mod.rs should register ${moduleName}`,
    );
  }
  const workflowMod = fs.readFileSync(path.join(workflowDir, 'mod.rs'), 'utf8');
  for (const moduleName of expectedWorkflowModules) {
    assert.match(
      workflowMod,
      rustModuleDeclarationPattern(moduleName),
      `workflow tests/mod.rs should register ${moduleName}`,
    );
  }

  const tauriModuleFiles = fs
    .readdirSync(tauriDir)
    .filter((fileName) => fileName.endsWith('.rs') && fileName !== 'mod.rs')
    .sort();
  assert.deepEqual(
    tauriModuleFiles,
    expectedTauriModules.map((name) => `${name}.rs`).sort(),
    'Tauri calendar subscription test files should remain a focused set',
  );

  const workflowModuleFiles = fs
    .readdirSync(workflowDir)
    .filter((fileName) => fileName.endsWith('.rs') && fileName !== 'mod.rs')
    .sort();
  assert.deepEqual(
    workflowModuleFiles,
    expectedWorkflowModules.map((name) => `${name}.rs`).sort(),
    'workflow calendar subscription test files should remain a focused set',
  );

  const tauriSources = Object.fromEntries(
    expectedTauriModules.map((moduleName) => [
      moduleName,
      fs.readFileSync(path.join(tauriDir, `${moduleName}.rs`), 'utf8'),
    ]),
  );
  const workflowSources = Object.fromEntries(
    expectedWorkflowModules.map((moduleName) => [
      moduleName,
      fs.readFileSync(path.join(workflowDir, `${moduleName}.rs`), 'utf8'),
    ]),
  );

  const expectedTauriOwnership = {
    fetch: [
      'captive_portal_body_detects_html_without_doctype',
      'captive_portal_body_rejects_empty_body',
    ],
    fetch_body: [
      'read_body_capped_accepts_body_under_limit',
      'ics_fetch_aborts_after_idle_gap_exceeds_window',
    ],
    mutations: [
      'add_calendar_subscription_with_conn_inserts_row_with_enabled_default',
      'toggle_calendar_subscription_with_conn_flips_enabled_flag',
    ],
    source_contract: [
      'calendar_subscription_ipc_results_are_typed_structs_not_free_form_json',
    ],
    sync: [
      'fetch_ics_preserves_cached_events_on_truncation_rejection',
      'detect_ics_truncation_matches_case_insensitively',
      'sync_subscription_content_inner_skips_writes_when_subscription_disabled_mid_apply',
    ],
  };

  const expectedWorkflowOwnership = {
    parse_core: [
      'parse_ics_events_skips_malformed_vevent_datetime',
    ],
    parse_properties: [
      'rrule_to_json_weekly_with_byday',
    ],
    parse_recurrence: [
      'parse_exdate_with_z_suffix_keeps_utc_date',
      'parse_exdate_with_tzid_resolves_to_utc_date',
      'parse_recurrence_id_tzid_and_z_form_collapse_to_same_key',
    ],
    parse_truncation: [
      'fetch_ics_rejects_body_without_end_vcalendar',
      'parse_ics_rejects_mismatched_begin_end_vevent_count',
      'fetch_ics_accepts_well_formed_feed',
    ],
    parse_vtimezone: [
      'vtimezone_block_drives_utc_conversion_for_summer_event',
      'vtimezone_block_only_applies_to_its_own_tzid',
    ],
    scheduling: [
      'rate_limit_cooldown_adds_retry_after_seconds_to_now',
      'rate_limit_cooldown_clamps_hostile_retry_after_values',
    ],
    tzid: [
      'parse_ics_datetime_maps_pacific_standard_time_to_iana',
      'resolve_tzid_to_iana_returns_none_for_unknown_name',
    ],
    validation: [
      'validate_ics_url_rejects_domain_resolving_to_private_range',
    ],
  };

  for (const [moduleName, functionNames] of Object.entries(expectedTauriOwnership)) {
    for (const functionName of functionNames) {
      assert.match(
        tauriSources[moduleName],
        new RegExp(`\\nfn ${functionName}\\(`),
        `Tauri ${moduleName}.rs should own ${functionName}`,
      );
    }
  }
  for (const [moduleName, functionNames] of Object.entries(expectedWorkflowOwnership)) {
    for (const functionName of functionNames) {
      assert.match(
        workflowSources[moduleName],
        new RegExp(`\\nfn ${functionName}\\(`),
        `workflow ${moduleName}.rs should own ${functionName}`,
      );
    }
  }
});
