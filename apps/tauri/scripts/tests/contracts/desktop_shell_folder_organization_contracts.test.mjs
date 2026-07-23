import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { hasRustUseReexport, readRustSources, repoRoot } from './shared.mjs';

test('desktop_shell is organized as a folder-backed subsystem with focused tray and popover modules', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/desktop_shell/mod.rs'),
    'utf8',
  );
  const shellSource = readRustSources('app/src-tauri/src/desktop_shell');

  assert.match(rootSource, /^mod popover;$/m);
  assert.match(rootSource, /^mod tray;$/m);
  assert.ok(
    hasRustUseReexport(rootSource, {
      modulePath: 'popover',
      symbols: ['hide_auxiliary_desktop_windows', 'install_popover_close_to_hide'],
      visibility: 'pub(crate)',
    }),
    'desktop_shell root should re-export popover wiring from popover.rs',
  );
  assert.ok(
    hasRustUseReexport(rootSource, {
      modulePath: 'tray',
      symbols: 'setup_system_tray',
      visibility: 'pub(crate)',
    }),
    'desktop_shell root should re-export tray wiring',
  );
  assert.doesNotMatch(
    rootSource,
    /\nfn attach_popover_close_to_hide\(|\nfn ensure_popover_window\(|\npub\(crate\) fn setup_system_tray\(/,
    'desktop_shell/mod.rs should remain a composition root after subtree extraction',
  );

  assert.match(shellSource, /fn attach_popover_close_to_hide\(/);
  assert.match(shellSource, /fn ensure_popover_window\(/);
  assert.match(shellSource, /pub\(crate\) fn hide_auxiliary_desktop_windows\(/);
  assert.match(shellSource, /pub\(crate\) fn setup_system_tray\(/);
});

test('macOS menu design doc stays aligned with localized runtime menu ids and labels', () => {
  const menuDocSource = fs.readFileSync(
    path.join(repoRoot, 'docs/design/MACOS_MENU_BAR.md'),
    'utf8',
  );
  const menuRuntimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/desktop_shell/app_menu.rs'),
    'utf8',
  );
  const menuI18nSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/menu_i18n.rs'),
    'utf8',
  );

  assert.match(menuDocSource, /`export_data` \/ `import_data`/);
  assert.match(menuDocSource, /\| Export Data\.\.\. \| `export_data` \|/);
  assert.match(menuDocSource, /\| Import Data\.\.\. \| `import_data` \|/);
  assert.doesNotMatch(menuDocSource, /export_snapshot|import_snapshot/);
  assert.doesNotMatch(menuDocSource, /English-only/);
  assert.match(menuDocSource, /localized in Rust before the frontend loads/i);
  assert.match(menuDocSource, /generated from the canonical JSON locale catalogs/i);

  assert.match(menuRuntimeSource, /with_id\("export_data"/);
  assert.match(menuRuntimeSource, /with_id\("import_data"/);
  assert.match(menuI18nSource, /menu_i18n\.generated\.rs/);
  assert.match(menuI18nSource, /\bExportData,/);
  assert.match(menuI18nSource, /\bImportData,/);
  assert.doesNotMatch(menuI18nSource, /\("zh",\s*MenuKey::\w+\)\s*=>/);
});
