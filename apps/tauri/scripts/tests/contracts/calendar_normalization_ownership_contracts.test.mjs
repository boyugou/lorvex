import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('calendar create/update normalization is owned by lorvex-workflow', () => {
  const workflowSource = readRustSources('lorvex-workflow/src/calendar_normalization');
  assert.match(workflowSource, /pub fn normalize_calendar_create\(/);
  assert.match(workflowSource, /pub fn normalize_calendar_update\(/);
  assert.match(workflowSource, /resolve_local_datetime/);
  assert.match(workflowSource, /inject_bymonthday/);
  assert.match(workflowSource, /validate_user_url/);

  const adapters = [
    'app/src-tauri/src/commands/calendar/events/create/mod.rs',
    'app/src-tauri/src/commands/calendar/events/update/mod.rs',
    'mcp-server/src/calendar/mod.rs',
    'mcp-server/src/calendar/mutations/update/mod.rs',
  ];

  for (const relativePath of adapters) {
    const source = read(relativePath);
    assert.match(
      source,
      /normalize_calendar_(create|update)/,
      `${relativePath} should delegate calendar normalization to lorvex-workflow`,
    );
    assert.doesNotMatch(
      source,
      /validate_user_url|validate_hex_color|resolve_local_datetime|DstResolution|inject_bymonthday|check_calendar_event_dst|validate_calendar_event_fields/,
      `${relativePath} must stay a transport/storage adapter, not a calendar normalization owner`,
    );
  }
});
