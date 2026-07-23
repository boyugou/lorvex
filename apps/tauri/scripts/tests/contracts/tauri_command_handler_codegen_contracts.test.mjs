import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const buildRs = fs.readFileSync(path.join(repoRoot, 'app/src-tauri/build.rs'), 'utf8');
const libRs = fs.readFileSync(path.join(repoRoot, 'app/src-tauri/src/lib.rs'), 'utf8');
const commandsRs = fs.readFileSync(path.join(repoRoot, 'app/src-tauri/src/commands.rs'), 'utf8');

test('Tauri handler codegen emits module-qualified command paths', () => {
  assert.match(buildRs, /struct CommandHandler/);
  assert.match(buildRs, /module_path_for_command_source/);
  assert.match(buildRs, /body\.push_str\(&handler\.path\)/);
  assert.match(buildRs, /pub\(crate\) fn apply_invoke_handlers/);
  assert.doesNotMatch(buildRs, /use commands::\*/);
  assert.doesNotMatch(buildRs, /bare identifier/);
});

test('lib.rs delegates handler registration without command glob imports', () => {
  assert.match(libRs, /commands::apply_invoke_handlers\(builder\)/);
  assert.doesNotMatch(libRs, /^use commands::\*;$/m);
  assert.doesNotMatch(libRs, /^use calendar_subscription_sync::\*;$/m);
  assert.doesNotMatch(libRs, /^use calendar_subscription_sync::native::\*;$/m);
});

test('commands root has no broad unused-import allowance', () => {
  assert.match(commandsRs, /include!\(concat!\(env!\("OUT_DIR"\), "\/handler_inventory\.rs"\)\)/);
  assert.doesNotMatch(commandsRs, /#!\[allow\(unused_imports\)\]/);
});
