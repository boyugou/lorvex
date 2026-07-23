import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { hasRustUseReexport, rustModuleDeclarationPattern } from './shared.mjs';

const repoRoot = path.resolve(import.meta.dirname, '..', '..', '..');
const commandsPath = path.join(repoRoot, 'app', 'src-tauri', 'src', 'commands.rs');

test('commands root delegates calendar event commands and types to a dedicated module', () => {
  const source = fs.readFileSync(commandsPath, 'utf8');

  assert.match(source, rustModuleDeclarationPattern('calendar'));
  assert.equal(hasRustUseReexport(source, {
    visibility: 'pub(crate)',
    modulePath: 'calendar::events',
    symbols: ['CalendarEvent', 'normalize_calendar_recurrence'],
  }), true);
  assert.equal(hasRustUseReexport(source, {
    visibility: 'pub',
    modulePath: 'calendar::events',
    symbols: [
      'create_calendar_event',
      'update_calendar_event',
      'delete_calendar_event',
      'get_events_by_date_range',
    ],
  }), false);

  const inlineLegacyShapes = [
    'pub struct CalendarEvent',
    'const EVENT_COLS',
    'fn event_from_row',
    'fn normalize_calendar_recurrence(',
    'fn validate_calendar_event_fields',
    'fn create_calendar_event_internal',
    'fn update_calendar_event_internal',
    '#[tauri::command]\npub fn create_calendar_event',
    '#[tauri::command]\npub fn update_calendar_event',
    '#[tauri::command]\npub fn delete_calendar_event',
    '#[tauri::command]\npub fn get_events_by_date_range',
    'fn expand_calendar_event_for_range(',
  ];

  for (const snippet of inlineLegacyShapes) {
    assert.equal(
      source.includes(snippet),
      false,
      `commands.rs should no longer inline calendar event implementation snippet: ${snippet}`,
    );
  }
});
