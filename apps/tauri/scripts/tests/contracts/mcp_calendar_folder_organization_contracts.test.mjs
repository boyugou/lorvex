import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

test('server_calendar is organized as a folder-backed subsystem with mutations and queries modules', () => {
  const rootSource = fs.readFileSync(path.join(repoRoot, 'mcp-server/src/calendar/mod.rs'), 'utf8');
  const mutationsSource = readRustSources(
    'mcp-server/src/calendar/mutations',
  );
  const queriesSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/calendar/queries.rs'),
    'utf8',
  );

  assert.match(rootSource, /^mod mutations;$/m);
  assert.match(rootSource, /^mod queries;$/m);
  assert.match(rootSource, /^mod exceptions;$/m);
  assert.match(rootSource, /^mod provider_event_links;$/m);
  assert.match(rootSource, /^mod task_calendar_event_links;$/m);
  assert.match(
    rootSource,
    /pub\(crate\) use mutations::\{/,
    'server_calendar root should re-export mutation entrypoints',
  );
  assert.match(
    rootSource,
    /^pub\(crate\) use queries::\{get_calendar_event, get_calendar_events, search_calendar_events\};$/m,
  );
  assert.doesNotMatch(
    rootSource,
    /\npub\(crate\) fn create_calendar_event\(|\npub\(crate\) fn update_calendar_event\(|\npub\(crate\) fn get_calendar_events\(/,
    'server_calendar root should remain preparation/model glue after folder extraction',
  );
  assert.match(mutationsSource, /\npub\(crate\) fn create_calendar_event\(/);
  assert.match(mutationsSource, /\npub\(crate\) fn batch_create_calendar_events\(/);
  assert.match(mutationsSource, /\npub\(crate\) fn update_calendar_event\(/);
  assert.match(mutationsSource, /\npub\(super\) fn load_calendar_event_json\(/);
  assert.match(queriesSource, /\npub\(crate\) fn get_calendar_events\(/);
});
