import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, readRustSources, repoRoot, rustModuleDeclarationPattern } from './shared.mjs';

test('planning commands are organized as a focused folder-backed module tree', () => {
  const planningDir = path.join(repoRoot, 'app/src-tauri/src/commands/planning');
  const modSource = fs.readFileSync(path.join(planningDir, 'mod.rs'), 'utf8');
  const currentFocusSource = fs.readFileSync(path.join(planningDir, 'current_focus.rs'), 'utf8');
  const reorderRootSource = fs.readFileSync(path.join(planningDir, 'reorder/mod.rs'), 'utf8');
  const reorderSource = readRustSources('app/src-tauri/src/commands/planning/reorder');
  const focusScheduleSource = readRustSources(
    'app/src-tauri/src/commands/planning/focus_schedule.rs',
    'app/src-tauri/src/commands/planning/focus_schedule',
  );

  assert.equal(
    fs.existsSync(path.join(repoRoot, 'app/src-tauri/src/commands/planning.rs')),
    false,
    'planning.rs should be replaced by a folder-backed planning module tree',
  );

  for (const moduleName of ['current_focus', 'reorder', 'focus_schedule']) {
    assert.match(
      modSource,
      rustModuleDeclarationPattern(moduleName),
      `planning/mod.rs should register ${moduleName}`,
    );
  }

  assert.equal(
    hasRustUseReexport(modSource, {
      modulePath: 'current_focus',
      symbols: ['get_current_focus'],
    }),
    true,
    'planning/mod.rs should re-export get_current_focus from current_focus.rs',
  );
  assert.equal(
    hasRustUseReexport(modSource, {
      modulePath: 'reorder',
      symbols: ['reorder_current_focus_open_tasks'],
    }),
    true,
    'planning/mod.rs should re-export reorder IPC commands from the reorder subtree',
  );
  assert.equal(
    hasRustUseReexport(modSource, {
      modulePath: 'focus_schedule',
      symbols: ['get_focus_schedule'],
    }),
    true,
    'planning/mod.rs should re-export get_focus_schedule from focus_schedule.rs',
  );
  assert.doesNotMatch(
    modSource,
    /\n#\[tauri::command\]\npub fn get_current_focus\(|\n#\[tauri::command\]\npub fn reorder_current_focus_open_tasks\(|\n#\[tauri::command\]\npub fn get_focus_schedule\(/,
    'planning/mod.rs should remain a composition layer after extraction',
  );

  assert.match(currentFocusSource, /\n#\[tauri::command\]\npub fn get_current_focus\(/);
  // `today_ymd_for_conn` was promoted into `lorvex_workflow::timezone`
  // so the planning command no longer needs its own local helper. Match
  // either the new fully-qualified call or a still-imported alias path.
  assert.match(
    currentFocusSource,
    /let today = (?:(?:lorvex_workflow|lorvex_store::shared_ops)::timezone::)?today_ymd_for_conn\(&conn\)/,
  );
  assert.match(reorderRootSource, rustModuleDeclarationPattern('current_focus'));
  assert.match(reorderRootSource, rustModuleDeclarationPattern('shared'));
  assert.equal(
    hasRustUseReexport(reorderRootSource, {
      modulePath: 'current_focus',
      symbols: ['reorder_current_focus_open_tasks'],
    }),
    true,
    'planning/reorder/mod.rs should re-export reorder_current_focus_open_tasks from current_focus.rs',
  );
  assert.doesNotMatch(
    reorderRootSource,
    /\n#\[tauri::command\]\npub fn reorder_current_focus_open_tasks\(/,
    'planning/reorder/mod.rs should stay as a composition layer over the reorder subtree',
  );
  assert.match(reorderSource, /\n#\[tauri::command\]\npub fn reorder_current_focus_open_tasks\(/);
  assert.match(reorderSource, /fn normalize_requested_task_ids\(/);
  assert.match(focusScheduleSource, /\n#\[tauri::command\]\npub fn get_focus_schedule\(/);
  assert.match(
    focusScheduleSource,
    /let today = (?:(?:lorvex_workflow|lorvex_store::shared_ops)::timezone::)?today_ymd_for_conn\(&conn\)/,
  );
});
