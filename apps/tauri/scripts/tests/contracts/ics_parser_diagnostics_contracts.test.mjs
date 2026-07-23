import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

test('ICS subscription parser returns structured diagnostics instead of writing stdout or stderr', () => {
  // ICS parsing lives in lorvex-workflow now (#3066 lift); the Tauri
  // subscription_sync module is a thin orchestration shell that calls
  // the workflow parse + sync facades. Diagnostics + structured warning
  // surfaces are owned by the workflow tree.
  const parseFacadeSource = fs.readFileSync(
    path.join(repoRoot, 'lorvex-workflow/src/calendar_subscription/parse/mod.rs'),
    'utf8',
  );
  const parseModelSource = fs.readFileSync(
    path.join(repoRoot, 'lorvex-workflow/src/calendar_subscription/parse/model.rs'),
    'utf8',
  );
  const syncSource = readRustSources('lorvex-workflow/src/calendar_subscription/sync');

  for (const [label, source] of [
    ['parser', parseFacadeSource],
    ['sync', syncSource],
  ]) {
    assert.doesNotMatch(
      source,
      /\b(?:eprintln|println|eprint|print|dbg)!\s*\(/,
      `ICS subscription ${label} code must persist structured warnings instead of printing directly`,
    );
  }
  assert.match(parseModelSource, /struct IcsParseWarning \{/);
  assert.match(parseFacadeSource, /parse_ics_events_with_diagnostics/);
  assert.match(syncSource, /persist_ics_parse_warnings/);
});
