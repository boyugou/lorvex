import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';

const repoRoot = path.resolve(import.meta.dirname, '..', '..', '..');

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('cancel-series recurrence clear uses caller-owned surface HLC versions', () => {
  const workflowCancel = read('lorvex-workflow/src/lifecycle/cancel.rs');
  const workflowEffects = read('lorvex-workflow/src/lifecycle/effects.rs');
  const tauriEffects = [
    read('app/src-tauri/src/commands/tasks/lifecycle/removal/cancel.rs'),
    read('app/src-tauri/src/commands/tasks/batch/cancel.rs'),
  ].join('\n');
  const mcpEffects = [
    read('mcp-server/src/tasks/lifecycle/writes/cancel.rs'),
    read('mcp-server/src/tasks/batch/cancel_by_ids/mod.rs'),
  ].join('\n');
  const cliEffects = read('lorvex-cli/src/commands/mutate/tasks/lifecycle_effects/mod.rs');

  assert.doesNotMatch(
    workflowCancel,
    /HlcSurface::App|HlcState::new|get_or_create_device_id|device_id_to_hlc_suffix|observe_local_event/,
    'workflow cancel-series must not mint an App-suffixed recurrence-clear HLC locally',
  );
  assert.match(
    workflowCancel,
    /series_clear_version:\s+Option<&str>/,
    'workflow cancel transition should accept the caller-supplied recurrence-clear HLC',
  );
  assert.match(
    workflowCancel,
    /requires a caller-supplied HLC version/,
    'workflow cancel transition should fail closed if the caller omits the second HLC',
  );

  assert.match(
    workflowEffects,
    /let\s+reminder_ver\s+=\s+hlc\.next_version_string\(\);/,
    'shared run_cancel should mint the status/reminder HLC through the caller-owned session',
  );
  assert.match(
    workflowEffects,
    /let\s+series_clear_ver\s+=\s+if\s+cancel_series\s+\{\s+Some\(hlc\.next_version_string\(\)\)\s+\}\s+else\s+\{\s+None\s+\};/,
    'shared run_cancel should mint the recurrence-clear HLC through the same caller-owned session',
  );
  assert.match(
    workflowEffects,
    /series_clear_ver\.as_deref\(\)/,
    'shared run_cancel should pass the caller-owned second HLC into apply_cancel_transition',
  );

  assert.match(
    tauriEffects,
    /workflow_effects::run_cancel\([\s\S]*hlc[\s\S]*\)/,
    'Tauri cancel lifecycle should provide the App surface HLC session at its boundary',
  );
  assert.match(
    mcpEffects,
    /workflow_effects::run_cancel\([\s\S]*hlc[\s\S]*\)/,
    'MCP cancel lifecycle should provide the MCP surface HLC session at its boundary',
  );
  assert.match(
    cliEffects,
    /workflow_lifecycle_effects::run_cancel\([\s\S]*hlc[\s\S]*\)/,
    'CLI cancel lifecycle should provide the CLI surface HLC session at its boundary',
  );
});
