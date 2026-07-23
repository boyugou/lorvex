import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

// ICS parsing was lifted into lorvex-workflow (#3066). The parse facade
// now lives at lorvex-workflow/src/calendar_subscription/parse/mod.rs
// and delegates to the same builder/datetime/dedupe/metadata/model/
// properties/rrule submodules; the Tauri tree consumes parse_ics_events
// + rrule_to_json from the workflow re-export.
const PARSE_FACADE = 'lorvex-workflow/src/calendar_subscription/parse/mod.rs';

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('ICS parser delegates bounded helper domains to focused modules', () => {
  const rootSource = read(PARSE_FACADE);
  const rruleSource = read('lorvex-workflow/src/calendar_subscription/parse/rrule.rs');
  const metadataSource = read('lorvex-workflow/src/calendar_subscription/parse/metadata.rs');
  const datetimeSource = read('lorvex-workflow/src/calendar_subscription/parse/datetime.rs');
  const propertiesSource = read('lorvex-workflow/src/calendar_subscription/parse/properties.rs');
  const modelSource = read('lorvex-workflow/src/calendar_subscription/parse/model.rs');
  const builderSource = read('lorvex-workflow/src/calendar_subscription/parse/builder.rs');
  const dedupeSource = read('lorvex-workflow/src/calendar_subscription/parse/dedupe.rs');

  for (const moduleName of [
    'builder',
    'datetime',
    'dedupe',
    'metadata',
    'model',
    'properties',
    'rrule',
  ]) {
    assert.match(
      rootSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `parse/mod.rs should register ${moduleName}.rs`,
    );
  }
  assert.match(
    rootSource,
    /pub use rrule::\{[^}]*rrule_to_json[^}]*\}/,
    'parse/mod.rs should preserve the RRULE public surface through re-export',
  );
  assert.ok(
    rootSource.split('\n').length <= 240,
    'parse/mod.rs should stay a small parse orchestration facade after extraction',
  );
  assert.doesNotMatch(
    rootSource,
    /\n(?:pub(?:\([^)]+\))?\s+)?fn rrule_to_json\b|\nfn parse_rrule_i64\b|\nfn extract_calendar_method\b|\nfn unfold_lines\b|\nfn normalize_ics_datetime_to_date\b|\nfn strip_mailto_scheme\b|\n(?:pub(?:\([^)]+\))?\s+)?fn unescape_ics\b|\n(?:pub(?:\([^)]+\))?\s+)?struct ParsedEvent\b|\n(?:pub(?:\([^)]+\))?\s+)?struct IcsParseReport\b|\n(?:pub(?:\([^)]+\))?\s+)?struct IcsParseWarning\b|\nstruct EventBuilder\b|\nimpl EventBuilder\b|\nfn merge_duplicate_events\b|\nfn event_supersedes\b/,
    'parse/mod.rs should not keep extracted helper, model, builder, or dedupe implementations inline',
  );

  assert.match(modelSource, /\npub(?:\(crate\))? struct IcsParseReport\b/);
  assert.match(modelSource, /\npub(?:\(crate\))? struct IcsParseWarning\b/);
  assert.match(modelSource, /\npub(?:\(crate\))? struct ParsedEvent\b/);
  assert.match(modelSource, /\npub\(super\) const MAX_EXDATES_PER_EVENT\b/);
  assert.match(modelSource, /\npub\(super\) const MAX_VEVENTS_PER_FEED\b/);
  assert.doesNotMatch(modelSource, /\nfn parse_ics_events\b|\nstruct EventBuilder\b|\nfn merge_duplicate_events\b/);

  assert.match(builderSource, /\npub\(super\) struct EventBuilder\b/);
  assert.match(builderSource, /\nimpl EventBuilder\b/);
  assert.match(builderSource, /\n\s+pub\(super\) fn parse_line\b/);
  assert.match(builderSource, /\n\s+pub\(super\) fn build\b/);
  assert.match(builderSource, /MAX_EXDATES_PER_EVENT/);
  assert.match(builderSource, /parse_ics_datetime_with_registry/);
  assert.doesNotMatch(builderSource, /\nfn parse_ics_events\b|\nfn merge_duplicate_events\b/);

  assert.match(dedupeSource, /\npub\(super\) fn merge_duplicate_events\b/);
  assert.match(dedupeSource, /\nfn event_supersedes\b/);
  assert.match(dedupeSource, /HashMap/);
  assert.doesNotMatch(dedupeSource, /\nstruct EventBuilder\b|\nfn parse_ics_events\b/);

  assert.match(rruleSource, /\npub(?:\(crate\))? fn rrule_to_json\b/);
  assert.match(
    rruleSource,
    /lorvex_domain::calendar_ics::parse_ics_rrule_to_recurrence_json\b/,
    'RRULE parsing should be owned by lorvex-domain, with the workflow keeping only the adapter surface',
  );
  assert.doesNotMatch(
    rruleSource,
    /\nfn parse_rrule_i64\b|\nfn parse_rrule_i64_list\b|normalize_calendar_recurrence/,
    'RRULE adapter should not keep duplicate RRULE parsing or normalization logic',
  );
  assert.match(metadataSource, /\npub\(super\) fn extract_calendar_method\b/);
  assert.match(metadataSource, /\npub\(super\) fn unfold_lines\b/);
  assert.match(datetimeSource, /\npub\(super\) fn normalize_ics_datetime_to_date\b/);
  assert.match(datetimeSource, /\npub\(super\) fn normalize_recurrence_id\b/);
  assert.match(propertiesSource, /\npub\(crate\) fn extract_ics_param\b/);
  assert.match(propertiesSource, /\npub\(crate\) fn unescape_ics\b/);
});
