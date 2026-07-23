import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot, rustModuleDeclarationPattern } from './shared.mjs';

test('commands root delegates shared models and db helpers to a dedicated shared module tree', () => {
  const commandsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands.rs'),
    'utf8',
  );
  const sharedRootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/commands/shared/mod.rs'),
    'utf8',
  );
  const sharedSource = readRustSources(
    'app/src-tauri/src/commands/shared/mod.rs',
    'app/src-tauri/src/commands/shared',
  );

  assert.match(commandsSource, rustModuleDeclarationPattern('shared'));
  for (const exportName of ['Task', 'TaskList', 'ListWithCount', 'Overview']) {
    assert.match(
      commandsSource,
      new RegExp(`^pub use shared::\\{[\\s\\S]*\\b${exportName}\\b[\\s\\S]*\\};$`, 'm'),
      `commands.rs should re-export ${exportName} from the shared module tree`,
    );
  }
  for (const exportName of ['fetch_task_by_id', 'task_from_row', 'TASK_COLS']) {
    assert.match(
      commandsSource,
      new RegExp(`^pub\\(crate\\) use shared::\\{[\\s\\S]*\\b${exportName}\\b[\\s\\S]*\\};$`, 'm'),
      `commands.rs should re-export ${exportName} from the shared module tree`,
    );
  }
  assert.match(sharedRootSource, rustModuleDeclarationPattern('constants'));
  assert.match(sharedRootSource, rustModuleDeclarationPattern('models'));
  assert.match(sharedRootSource, rustModuleDeclarationPattern('task_rows'));
  // `utilities` was further decomposed into focused submodules
  // (chrono_helpers, numeric, json_helpers, id_validation,
  // path_validation, db_error_sanitize, limits, list_rows,
  // spotlight_dispatch). Verify that decomposition stays in place.
  for (const submodule of [
    'chrono_helpers',
    'db_error_sanitize',
    'id_validation',
    'json_helpers',
    'limits',
    'list_rows',
    'numeric',
    'path_validation',
    'spotlight_dispatch',
  ]) {
    assert.match(
      sharedRootSource,
      rustModuleDeclarationPattern(submodule),
      `commands/shared should register the ${submodule} submodule`,
    );
  }
  for (const fileName of [
    'constants.rs',
    'models.rs',
    'task_rows.rs',
    'chrono_helpers.rs',
    'numeric.rs',
    'json_helpers.rs',
    'id_validation.rs',
    'path_validation.rs',
    'db_error_sanitize.rs',
    'limits.rs',
    'list_rows.rs',
    'spotlight_dispatch.rs',
  ]) {
    assert.ok(
      fs.existsSync(path.join(repoRoot, 'app/src-tauri/src/commands/shared', fileName)),
      `commands/shared should include ${fileName}`,
    );
  }
  assert.doesNotMatch(
    commandsSource,
    /\npub struct Task \{|\npub struct TaskList \{|\npub struct ListWithCount \{|\npub struct Overview \{|\nconst TASK_COLS: &str =|\nfn task_from_row\(|\nfn tasks_from_query\(|\nfn fetch_task_by_id\(/,
    'commands.rs should not keep shared models or core task-row helpers inline after extraction',
  );
  for (const pattern of [
    /\npub struct Task \{/,
    /\npub struct TaskList \{/,
    /\npub struct ListWithCount \{/,
    /\npub struct Overview \{/,
    /\npub const TASK_COLS: &str =/,
    /\npub\(crate\) fn task_from_row\(/,
    /\npub\(crate\) fn tasks_from_query\(/,
    /\npub\(crate\) fn fetch_task_by_id\(/,
  ]) {
    assert.match(sharedSource, pattern, 'shared/ should own shared IPC models and task row helpers');
  }
});
