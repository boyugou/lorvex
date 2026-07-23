import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('assistant UI runtime organizes tests as a coherent folder-backed module tree', () => {
  const testsDir = path.join(repoRoot, 'mcp-server/src/preferences/ui/tests');
  const modPath = path.join(testsDir, 'mod.rs');
  const appearancePath = path.join(testsDir, 'appearance_and_language.rs');
  const navigationPath = path.join(testsDir, 'navigation.rs');
  const sharedContractsPath = path.join(testsDir, 'shared_contracts.rs');
  const taskTargetingPath = path.join(testsDir, 'task_targeting.rs');

  assert.ok(fs.existsSync(modPath), 'server_preferences_ui/tests/mod.rs should exist');
  assert.ok(
    fs.existsSync(appearancePath),
    'server_preferences_ui/tests/appearance_and_language.rs should exist',
  );
  assert.ok(fs.existsSync(navigationPath), 'server_preferences_ui/tests/navigation.rs should exist');
  assert.ok(
    fs.existsSync(sharedContractsPath),
    'server_preferences_ui/tests/shared_contracts.rs should exist',
  );
  assert.ok(
    fs.existsSync(taskTargetingPath),
    'server_preferences_ui/tests/task_targeting.rs should exist',
  );

  const modSource = fs.readFileSync(modPath, 'utf8');
  assert.match(modSource, /^mod appearance_and_language;$/m);
  assert.match(modSource, /^mod navigation;$/m);
  assert.match(modSource, /^mod shared_contracts;$/m);
  assert.match(modSource, /^mod task_targeting;$/m);
  assert.match(modSource, /fn shared_assistant_ui_actions\(\) -> Vec<String>/);
  assert.match(modSource, /fn open_temp_db\(\) -> Connection/);
  assert.match(modSource, /fn seed_list\(conn: &Connection, id: &str\)/);
  assert.match(modSource, /fn seed_task\(conn: &Connection, id: &str, status: &str\)/);

  assert.match(
    fs.readFileSync(sharedContractsPath, 'utf8'),
    /rust_assistant_ui_actions_match_shared_contract/,
  );
  assert.match(
    fs.readFileSync(appearancePath, 'utf8'),
    /control_app_ui_accepts_shared_theme_modes/,
  );
  assert.match(
    fs.readFileSync(appearancePath, 'utf8'),
    /control_app_ui_accepts_valid_language_values/,
  );
  assert.match(
    fs.readFileSync(navigationPath, 'utf8'),
    /control_app_ui_accepts_valid_switch_view_values/,
  );
  assert.match(
    fs.readFileSync(taskTargetingPath, 'utf8'),
    /control_app_ui_accepts_enter_focus_mode_for_open_target_tasks/,
  );
});
