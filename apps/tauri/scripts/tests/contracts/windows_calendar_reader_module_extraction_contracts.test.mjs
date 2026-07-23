import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const ROOT = 'app/src-tauri/src/platform/windows_calendar.rs';
const READER = 'app/src-tauri/src/platform/windows_calendar/reader.rs';

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('Windows calendar reader delegates helper domains to focused modules', () => {
  const rootSource = read(ROOT);
  const readerSource = read(READER);
  const propertiesSource = read('app/src-tauri/src/platform/windows_calendar/reader/properties.rs');
  const sourceTimeSource = read('app/src-tauri/src/platform/windows_calendar/reader/source_time.rs');
  const requestStoreSource = read('app/src-tauri/src/platform/windows_calendar/reader/request_store.rs');
  const attendeesSource = read('app/src-tauri/src/platform/windows_calendar/reader/attendees.rs');
  const recurrenceSource = read('app/src-tauri/src/platform/windows_calendar/reader/recurrence.rs');
  const testsSource = read('app/src-tauri/src/platform/windows_calendar/reader/tests.rs');

  assert.match(rootSource, /^pub mod reader;$/m);
  assert.doesNotMatch(rootSource, /pub mod reader\s*\{/);
  assert.ok(
    rootSource.split('\n').length <= 12,
    'windows_calendar.rs should only declare the reader module and top-level docs',
  );

  for (const moduleName of ['properties', 'source_time']) {
    assert.match(
      readerSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `reader.rs should register ${moduleName}.rs`,
    );
  }
  for (const moduleName of ['attendees', 'request_store']) {
    assert.match(
      readerSource,
      new RegExp(`^#\\[cfg\\(target_os = "windows"\\)\\]\\nmod ${moduleName};$`, 'm'),
      `reader.rs should register Windows-only ${moduleName}.rs`,
    );
  }
  assert.match(
    readerSource,
    /^mod recurrence;$/m,
    'reader.rs should register recurrence.rs on every target so pure contract tests compile off Windows',
  );
  assert.match(readerSource, /^#\[cfg\(test\)\]\nmod tests;$/m);
  assert.match(readerSource, /use properties::\{optional_windows_string, required_windows_value\};/);
  assert.match(readerSource, /use source_time::resolve_source_time_semantics;/);
  assert.match(readerSource, /use attendees::extract_windows_attendees;/);
  assert.match(readerSource, /use recurrence::extract_windows_recurrence;/);
  assert.match(readerSource, /use request_store::\{classify_request_store_error, denied_result, record_permission_denied\};/);
  assert.ok(
    readerSource.split('\n').length <= 520,
    'reader.rs should stay focused on sync orchestration after helper extraction',
  );
  assert.doesNotMatch(
    readerSource,
    /\nfn record_permission_denied\b|\nfn required_windows_value\b|\nfn optional_windows_string\b|\nstruct SourceTimeSemantics\b|\nfn resolve_source_time_semantics\b|\nfn denied_result\b|\nfn classify_request_store_error\b|\nfn extract_windows_attendees\b|\nfn extract_windows_recurrence\b|\nmod tests \{/,
    'reader.rs should not keep extracted helper implementations inline',
  );

  assert.match(propertiesSource, /\npub\(super\) fn required_windows_value\b/);
  assert.match(propertiesSource, /\npub\(super\) fn optional_windows_string\b/);
  assert.match(sourceTimeSource, /\npub\(super\) struct SourceTimeSemantics\b/);
  assert.match(sourceTimeSource, /\npub\(super\) fn resolve_source_time_semantics\b/);
  assert.match(requestStoreSource, /\npub\(super\) fn record_permission_denied\b/);
  assert.match(requestStoreSource, /\npub\(super\) fn denied_result\b/);
  assert.match(requestStoreSource, /\npub\(super\) fn classify_request_store_error\b/);
  assert.match(attendeesSource, /\npub\(super\) fn extract_windows_attendees\b/);
  assert.match(recurrenceSource, /\npub\(super\) fn extract_windows_recurrence\b/);
  assert.match(recurrenceSource, /normalize_calendar_recurrence/);
  assert.doesNotMatch(
    recurrenceSource,
    /map\.insert\("TZID"/,
    'Windows recurrence JSON must not store non-contract TZID keys',
  );
  assert.match(testsSource, /\nfn optional_windows_string_preserves_non_empty_values\(/);
  assert.match(testsSource, /\nfn resolve_source_time_semantics_initializes_timezone_once_when_missing\(/);
});
