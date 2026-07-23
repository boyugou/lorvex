import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('calendar event reads share the store projection across MCP Tauri and CLI', () => {
  const storeQueries = read('lorvex-store/src/calendar_timeline/queries/mod.rs');
  const mcpCalendarReads = [
    read('mcp-server/src/calendar/queries.rs'),
    read('mcp-server/src/calendar/mutations/mod.rs'),
  ].join('\n');
  const tauriEventsRoot = read('app/src-tauri/src/commands/calendar/events.rs');
  const tauriEventsQuery = read('app/src-tauri/src/commands/calendar/events/query.rs');
  const cliCalendarQuery = read('lorvex-cli/src/commands/query/calendar.rs');
  const cliCalendarLoad = read('lorvex-cli/src/commands/mutate/calendar/effects/load.rs');

  assert.match(
    storeQueries,
    /pub fn get_calendar_event\(/,
    'lorvex-store should expose the canonical single calendar event read path',
  );
  assert.match(
    storeQueries,
    /pub fn list_calendar_events\(/,
    'lorvex-store should expose the canonical calendar event list read path',
  );
  assert.match(
    storeQueries,
    /calendar_event_from_row/,
    'shared calendar reads should use the typed row mapper instead of JSON row passthrough',
  );

  assert.doesNotMatch(
    mcpCalendarReads,
    /SELECT\s+\*\s+FROM\s+calendar_events/i,
    'MCP calendar event reads must not use SELECT * against calendar_events',
  );
  assert.doesNotMatch(
    mcpCalendarReads,
    /query_(?:one|all)_as_json/,
    'MCP calendar event reads should adapt typed store rows instead of raw JSON SQL rows',
  );
  assert.match(
    mcpCalendarReads,
    /calendar_timeline::queries::(?:get|list)_calendar_event/,
    'MCP calendar event reads should call the shared store read path',
  );

  assert.doesNotMatch(
    tauriEventsRoot,
    /const EVENT_COLS|fn event_from_row/,
    'Tauri calendar events root should not own a separate read projection or row mapper',
  );
  assert.match(
    `${tauriEventsRoot}\n${tauriEventsQuery}`,
    /calendar_timeline::queries::get_calendar_event/,
    'Tauri get_calendar_event should call the shared store read path',
  );

  assert.match(
    cliCalendarQuery,
    /calendar_timeline::queries::get_calendar_event/,
    'CLI calendar show should call the shared store read path',
  );
  assert.match(
    cliCalendarLoad,
    /calendar_timeline::queries::get_calendar_event/,
    'CLI calendar mutation reloads should call the shared store read path',
  );
});
