import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot, rustModuleDeclarationPattern } from './shared.mjs';

test('calendar_events is organized as a folder-backed subsystem instead of a mixed root hotspot', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/calendar/events.rs'),
    'utf8',
  );
  const mutationsSource = readRustSources(
    'app/src-tauri/src/commands/calendar/events/create',
    'app/src-tauri/src/commands/calendar/events/update',
    'app/src-tauri/src/commands/calendar/events/delete.rs',
  );
  const querySource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/calendar/events/query.rs'),
    'utf8',
  );
  const validationSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/calendar/events/validation.rs'),
    'utf8',
  );

  for (const moduleName of ['create', 'delete', 'exceptions', 'ics_export', 'query', 'undo', 'update', 'validation']) {
    assert.match(
      rootSource,
      rustModuleDeclarationPattern(moduleName),
      `calendar_events root should register ${moduleName}`,
    );
  }

  assert.match(
    rootSource,
    /^pub use create::create_calendar_event;$/m,
    'calendar_events root should re-export create IPC surface from create',
  );
  assert.match(
    rootSource,
    /^pub use delete::\{delete_calendar_event, DeleteCalendarEventResult\};$/m,
    'calendar_events root should re-export delete IPC surface from delete',
  );
  assert.match(
    rootSource,
    /^pub use update::update_calendar_event;$/m,
    'calendar_events root should re-export update IPC surface from update',
  );
  assert.match(
    rootSource,
    /pub use query::\{[\s\S]*get_events_by_date_range[\s\S]*\};/m,
    'calendar_events root should re-export query IPC surface from query',
  );
  assert.match(
    rootSource,
    /pub\(crate\) use validation::parse_calendar_date;/m,
    'calendar_events root should expose validation helpers from validation',
  );
  assert.match(
    rootSource,
    /pub\(crate\) use validation::normalize_calendar_recurrence;/m,
    'calendar_events tests should expose recurrence normalization from validation',
  );
  assert.doesNotMatch(
    rootSource,
    /\n#\[tauri::command\]\npub fn create_calendar_event\(|\n#\[tauri::command\]\npub fn update_calendar_event\(|\n#\[tauri::command\]\npub fn delete_calendar_event\(|\n#\[tauri::command\]\npub fn get_events_by_date_range\(|\nfn create_calendar_event_internal\(|\npub\(crate\) fn normalize_calendar_recurrence\(/,
    'calendar_events root should remain a composition layer after folder extraction',
  );

  assert.match(mutationsSource, /\n#\[tauri::command\]\npub fn create_calendar_event\(/);
  assert.match(mutationsSource, /\n#\[tauri::command\]\npub fn update_calendar_event\(/);
  assert.match(mutationsSource, /\n#\[tauri::command\]\npub fn delete_calendar_event\(/);
  assert.match(mutationsSource, /fn update_calendar_event_internal\(/);
  assert.match(rootSource, /fn load_calendar_event\(/);
  assert.match(querySource, /\n#\[tauri::command\]\npub fn get_events_by_date_range\(/);
  assert.match(querySource, /get_calendar_timeline/);
  assert.match(validationSource, /pub\(crate\) fn normalize_calendar_recurrence\(/);
});
