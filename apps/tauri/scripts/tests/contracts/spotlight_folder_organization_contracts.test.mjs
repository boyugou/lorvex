import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

function assertCfgModule(source, cfg, moduleName) {
  assert.match(
    source,
    new RegExp(`^#\\[cfg\\(${cfg}\\)\\]\\nmod ${moduleName};$`, 'm'),
    `spotlight/mod.rs should gate ${moduleName} with #[cfg(${cfg})]`,
  );
}

function assertCfgUseAlias(source, cfg, moduleName) {
  assert.match(
    source,
    new RegExp(`^#\\[cfg\\(${cfg}\\)\\]\\nuse ${moduleName} as inner;$`, 'm'),
    `spotlight/mod.rs should map ${moduleName} to inner with #[cfg(${cfg})]`,
  );
}

test('platform spotlight is organized as a facade over shared and OS-specific modules', () => {
  const legacyPath = path.join(repoRoot, 'app/src-tauri/src/platform/spotlight.rs');
  const spotlightDir = path.join(repoRoot, 'app/src-tauri/src/platform/spotlight');
  const modSource = fs.readFileSync(path.join(spotlightDir, 'mod.rs'), 'utf8');

  assert.equal(
    fs.existsSync(legacyPath),
    false,
    'platform/spotlight.rs should stay replaced by a spotlight/ module tree',
  );

  // Post-#3303 split: macos.rs and windows.rs themselves became folders
  // (macos/{mod,attributes,per_task,query,reindex,tests}.rs and analogous
  // for windows). Verify both shared files and OS folders coexist.
  const expectedTopLevel = ['diagnostics.rs', 'mod.rs', 'noop.rs', 'queries.rs'];
  const actualTopLevel = fs
    .readdirSync(spotlightDir)
    .filter((entry) => entry.endsWith('.rs'))
    .sort();
  assert.deepEqual(actualTopLevel, expectedTopLevel, 'spotlight module tree file set drifted');
  for (const osDir of ['macos', 'windows']) {
    assert.equal(
      fs.statSync(path.join(spotlightDir, osDir)).isDirectory(),
      true,
      `spotlight should keep ${osDir}/ as a folder-backed OS surface`,
    );
    assert.equal(
      fs.existsSync(path.join(spotlightDir, osDir, 'mod.rs')),
      true,
      `spotlight ${osDir}/mod.rs should compose the OS-specific implementation`,
    );
  }

  const desktopCfg = 'any\\(target_os = "macos", target_os = "windows"\\)';
  const unsupportedCfg = 'not\\(any\\(target_os = "macos", target_os = "windows"\\)\\)';

  assertCfgModule(modSource, desktopCfg, 'diagnostics');
  assertCfgModule(modSource, 'target_os = "macos"', 'macos');
  assertCfgModule(modSource, unsupportedCfg, 'noop');
  assertCfgModule(modSource, desktopCfg, 'queries');
  assertCfgModule(modSource, 'target_os = "windows"', 'windows');
  assertCfgUseAlias(modSource, 'target_os = "macos"', 'macos');
  assertCfgUseAlias(modSource, unsupportedCfg, 'noop');
  assertCfgUseAlias(modSource, 'target_os = "windows"', 'windows');

  assert.doesNotMatch(
    modSource,
    /(?:^|\n)pub\s+mod (?:diagnostics|macos|noop|queries|windows);/m,
    'spotlight implementation modules must remain private',
  );

  const lines = modSource.split('\n');
  for (const [lineIndex, line] of lines.entries()) {
    if (!/^mod (?:diagnostics|macos|noop|queries|windows);$/.test(line)) {
      continue;
    }
    assert.match(
      lines[lineIndex - 1] ?? '',
      /^#\[cfg\(/,
      `${line} must be immediately preceded by a cfg gate`,
    );
  }

  assert.match(
    modSource,
    new RegExp(`^#\\[cfg\\(${desktopCfg}\\)\\]\\nuse diagnostics::log_spotlight_error;$`, 'm'),
    'spotlight error diagnostics should compile only on macOS/Windows',
  );
  assert.match(
    modSource,
    /^#\[cfg\(target_os = "windows"\)\]\nuse diagnostics::log_spotlight_warning;$/m,
    'jump-list unavailable diagnostics should compile only on Windows',
  );

  for (const publicSurface of [
    'pub use inner::reindex_all_tasks;',
    'pub(crate) use inner::reindex_tasks_by_ids;',
    'pub(crate) use inner::reindex_tasks_for_list;',
    'pub use inner::remove_all_tasks;',
    'pub(crate) use inner::remove_task;',
    'pub enum SpotlightAction',
    'pub fn apply_actions(',
  ]) {
    assert.match(
      modSource,
      new RegExp(publicSurface.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')),
      `spotlight facade should keep ${publicSurface}`,
    );
  }

  const queriesSource = fs.readFileSync(path.join(spotlightDir, 'queries.rs'), 'utf8');
  assert.match(queriesSource, /pub\(super\) const SELECT_INDEXABLE_TASK_PROJECTION/);
  assert.match(queriesSource, /pub\(super\) fn read_indexable_rows<P>\(/);
  assert.match(queriesSource, /pub\(super\) struct IndexableRow \{/);

  const diagnosticsSource = fs.readFileSync(path.join(spotlightDir, 'diagnostics.rs'), 'utf8');
  assert.match(diagnosticsSource, /pub\(super\) fn log_spotlight_error\(/);
  assert.match(diagnosticsSource, /pub\(super\) fn log_spotlight_warning\(/);

  // Post-#3303 split: macos.rs and windows.rs are folders now.
  const macosSource = readRustSources('app/src-tauri/src/platform/spotlight/macos');
  assert.match(macosSource, /use objc2_core_spotlight::\{/);
  assert.match(macosSource, /static REINDEX_IN_FLIGHT: AtomicBool/);
  assert.match(macosSource, /pub fn reindex_all_tasks\(\)/);
  assert.match(macosSource, /fn spotlight_io_is_disabled_in_unit_tests\(\)/);

  const windowsSource = readRustSources('app/src-tauri/src/platform/spotlight/windows');
  assert.match(
    windowsSource,
    /use crate::platform::com_apartment::ComApartmentGuard;/,
    'windows implementation should import COM apartment support from platform root',
  );
  assert.match(windowsSource, /static INDEXED_TASKS: Mutex<Option<HashMap<String, TaskRow>>>/);
  assert.match(windowsSource, /fn rebuild_jump_list_inner\(/);
  assert.match(windowsSource, /pub fn reindex_tasks_by_ids\(/);

  const noopSource = fs.readFileSync(path.join(spotlightDir, 'noop.rs'), 'utf8');
  assert.match(noopSource, /pub fn reindex_all_tasks\(\) \{\}/);
  assert.match(noopSource, /pub fn reindex_tasks_by_ids\(/);
});
