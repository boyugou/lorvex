import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('server_calendar mutations are organized as a folder-backed subsystem with create update and delete modules', () => {
  const mutationsRootSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/calendar/mutations/mod.rs'),
    'utf8',
  );
  const createSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/calendar/mutations/create.rs'),
    'utf8',
  );
  const updateSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/calendar/mutations/update/mod.rs'),
    'utf8',
  );
  const deleteSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/calendar/mutations/delete.rs'),
    'utf8',
  );

  for (const moduleName of ['create', 'delete', 'update']) {
    assert.match(
      mutationsRootSource,
      new RegExp(`^mod ${moduleName};$`, 'm'),
      `server_calendar mutations root should register ${moduleName}.rs`,
    );
  }

  assert.match(
    mutationsRootSource,
    /^pub\(crate\) use create::\{batch_create_calendar_events, create_calendar_event\};$/m,
    'server_calendar mutations root should re-export create entrypoints from create.rs',
  );
  assert.match(
    mutationsRootSource,
    /^pub\(crate\) use delete::delete_calendar_event;$/m,
    'server_calendar mutations root should re-export delete entrypoint from delete.rs',
  );
  assert.match(
    mutationsRootSource,
    /^pub\(crate\) use update::update_calendar_event;$/m,
    'server_calendar mutations root should re-export update entrypoint from update.rs',
  );
  assert.match(
    mutationsRootSource,
    /^pub\(super\) fn load_calendar_event_json\(/m,
    'server_calendar mutations root should own the shared calendar-event row loader',
  );
  assert.doesNotMatch(
    mutationsRootSource,
    /\npub\(crate\) fn create_calendar_event\(|\npub\(crate\) fn batch_create_calendar_events\(|\npub\(crate\) fn update_calendar_event\(|\npub\(crate\) fn delete_calendar_event\(/,
    'server_calendar mutations root should remain a composition layer after folder extraction',
  );

  assert.match(createSource, /\npub\(crate\) fn create_calendar_event\(/);
  assert.match(createSource, /\npub\(crate\) fn batch_create_calendar_events\(/);
  assert.match(updateSource, /\npub\(crate\) fn update_calendar_event\(/);
  assert.match(deleteSource, /\npub\(crate\) fn delete_calendar_event\(/);
});
