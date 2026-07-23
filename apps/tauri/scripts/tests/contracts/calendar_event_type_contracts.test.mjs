import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

const read = (relPath) => fs.readFileSync(path.join(repoRoot, relPath), 'utf8');

test('calendar IPC keeps canonical and mixed event surfaces distinct', () => {
  const ipcSource = read('app/src/lib/ipc/calendar.ts');
  // Post-#3303 split: create.rs became a folder; walk subtree.
  const tauriCreateSource = readRustSources('app/src-tauri/src/commands/calendar/events/create');
  const tauriUpdateSource = read('app/src-tauri/src/commands/calendar/events/update/command.rs');
  const mcpContractSource = read('mcp-server/src/contract/calendar/events.rs');
  const mcpCalendarSource = readRustSources('mcp-server/src/calendar');
  const exportCalendarRowWriterSource = read('lorvex-store/src/export/writers/calendar_event.rs');

  assert.match(
    ipcSource,
    /import type \{ CalendarEvent, CalendarEventType \} from '@lorvex\/shared\/types';/,
    'calendar IPC should import the shared canonical CalendarEventType',
  );
  assert.match(
    ipcSource,
    /event_type\?: CalendarEventType \| null;/,
    'createCalendarEvent should type event_type with the shared canonical CalendarEventType',
  );
  assert.match(
    ipcSource,
    /event_type\?: CalendarEventType;/,
    'updateCalendarEvent should type event_type with the shared canonical CalendarEventType',
  );
  assert.match(
    ipcSource,
    /export interface UnifiedCalendarEvent extends Omit<CalendarEvent, 'event_type'> \{/,
    'UnifiedCalendarEvent should stop inheriting the canonical event_type field directly from CalendarEvent',
  );
  assert.match(
    ipcSource,
    /event_type: string;/,
    'UnifiedCalendarEvent should keep mixed canonical\/provider event_type as a broad string surface',
  );
  assert.match(
    ipcSource,
    /export const getEventsByDateRange = \(from: string, to: string, signal\?: AbortSignal\): Promise<UnifiedCalendarEvent\[]> =>/,
    'getEventsByDateRange should expose the mixed timeline surface rather than pretending it returns canonical CalendarEvent rows',
  );
  assert.match(
    tauriCreateSource,
    /pub event_type: Option<CanonicalCalendarEventType>,/,
    'Tauri create args should deserialize canonical event_type into the shared enum at the command boundary',
  );
  assert.match(
    tauriUpdateSource,
    /Patch::Set\(raw\) => Patch::Set\(parse_canonical_event_type\(&raw\)\?\),/,
    'Tauri update args should strict-parse patch event_type into the shared enum at the command boundary',
  );
  assert.match(
    mcpContractSource,
    /enum CalendarEventTypeArg[\s\S]*Event,[\s\S]*Birthday,[\s\S]*Anniversary,[\s\S]*Memorial,/,
    'MCP contract should publish a typed canonical event_type enum instead of a raw string',
  );
  assert.match(
    mcpCalendarSource,
    /Patch<CanonicalCalendarEventType>/,
    'MCP calendar internals should normalize patch event_type into the shared canonical enum',
  );
  assert.match(
    exportCalendarRowWriterSource,
    /\.parse::<CanonicalCalendarEventType>\(\)/,
    'calendar export should parse canonical event_type before serializing archive payloads',
  );
});
