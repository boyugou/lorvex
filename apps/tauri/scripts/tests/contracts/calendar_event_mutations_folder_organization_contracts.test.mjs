import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, readRustSources, repoRoot, rustModuleDeclarationPattern } from './shared.mjs';

function readDeleteSource() {
  const fileForm = path.join(
    repoRoot,
    'app/src-tauri/src/commands/calendar/events/delete.rs',
  );
  if (fs.existsSync(fileForm)) return fs.readFileSync(fileForm, 'utf8');
  return readRustSources('app/src-tauri/src/commands/calendar/events/delete');
}

test('calendar event mutations are organized under the calendar events subsystem with create update and delete modules', () => {
  const eventsRootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/calendar/events.rs'),
    'utf8',
  );
  const createSource = readRustSources(
    'app/src-tauri/src/commands/calendar/events/create',
  );
  const updateRootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/calendar/events/update/mod.rs'),
    'utf8',
  );
  const updateSource = readRustSources(
    'app/src-tauri/src/commands/calendar/events/update',
  );
  const deleteSource = readDeleteSource();

  for (const moduleName of ['create', 'delete', 'update']) {
    assert.match(
      eventsRootSource,
      rustModuleDeclarationPattern(moduleName),
      `calendar events root should register ${moduleName}`,
    );
  }

  assert.equal(
    hasRustUseReexport(eventsRootSource, {
      modulePath: 'create',
      symbols: ['create_calendar_event'],
    }),
    true,
    'events root should re-export create IPC surface from create.rs',
  );
  assert.equal(
    hasRustUseReexport(eventsRootSource, {
      modulePath: 'delete',
      symbols: ['delete_calendar_event'],
    }),
    true,
    'events root should re-export delete IPC surface from delete.rs',
  );
  assert.equal(
    hasRustUseReexport(eventsRootSource, {
      modulePath: 'update',
      symbols: ['update_calendar_event'],
    }),
    true,
    'events root should re-export update IPC surface from update.rs',
  );
  assert.equal(
    hasRustUseReexport(eventsRootSource, {
      modulePath: 'update',
      symbols: ['update_calendar_event_internal'],
      visibility: 'crate',
    }),
    true,
    'events root should keep test-only update helpers behind cfg(test)',
  );
  assert.match(
    eventsRootSource,
    /^pub\(super\) fn load_calendar_event\(/m,
    'events root should own the shared event loader used by create/update flows',
  );
  assert.match(
    eventsRootSource,
    /^pub\(super\) fn load_optional_calendar_event\(/m,
    'events root should own the optional shared event loader used by delete/update flows',
  );
  assert.doesNotMatch(
    eventsRootSource,
    /\n#\[tauri::command\]\npub fn create_calendar_event\(|\n#\[tauri::command\]\npub fn update_calendar_event\(|\n#\[tauri::command\]\npub fn delete_calendar_event\(|\npub\(crate\) struct UpdateCalendarEventArgs \{/,
    'events root should stay a composition layer after dropping the redundant mutations middle layer',
  );

  assert.match(createSource, /\n#\[tauri::command\]\npub fn create_calendar_event\(/);
  assert.match(updateRootSource, rustModuleDeclarationPattern('command'));
  assert.doesNotMatch(updateRootSource, rustModuleDeclarationPattern('recurrence'));
  assert.equal(
    hasRustUseReexport(updateRootSource, {
      modulePath: 'command',
      symbols: ['update_calendar_event'],
    }),
    true,
    'update/mod.rs should re-export update_calendar_event from command.rs',
  );
  assert.equal(
    hasRustUseReexport(updateRootSource, {
      modulePath: 'command',
      symbols: ['wire_into_workflow_input'],
      visibility: 'crate',
    }),
    true,
    'update/mod.rs should keep the wire-to-workflow adapter re-exported for tests',
  );
  assert.doesNotMatch(
    updateRootSource,
    /\n#\[tauri::command\]\npub fn update_calendar_event\(/,
    'update/mod.rs should keep IPC command shape in command.rs',
  );
  assert.match(updateRootSource, /\npub\(crate\) fn update_calendar_event_internal\(/);
  assert.match(updateSource, /\npub\(crate\) fn update_calendar_event_internal\(/);
  assert.match(updateSource, /normalize_calendar_update/);
  assert.match(updateSource, /CalendarEventUpdateWire/);
  assert.match(updateSource, /CalendarEventUpdateInput/);
  assert.match(updateSource, /\n#\[tauri::command\]\npub fn update_calendar_event\(/);
  assert.match(deleteSource, /\n#\[tauri::command\]\npub fn delete_calendar_event\(/);
});
