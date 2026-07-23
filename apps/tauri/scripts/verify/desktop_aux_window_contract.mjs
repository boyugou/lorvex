#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_TAG = '[verify:desktop-aux-window-contract]';

function resolveRepoRoot() {
  const scriptPath = fileURLToPath(import.meta.url);
  return path.resolve(path.dirname(scriptPath), '..', '..');
}

function fail(message) {
  throw new Error(`${SCRIPT_TAG} ${message}`);
}

function assert(condition, message) {
  if (!condition) {
    fail(message);
  }
}

function readText(filePath) {
  assert(fs.existsSync(filePath), `missing file: ${path.relative(resolveRepoRoot(), filePath)}`);
  return fs.readFileSync(filePath, 'utf8');
}

function readRustModuleText(moduleRootPath) {
  const parts = [readText(moduleRootPath)];
  const moduleDir =
    path.basename(moduleRootPath) === 'mod.rs'
      ? path.dirname(moduleRootPath)
      : moduleRootPath.replace(/\.rs$/, '');
  if (!fs.existsSync(moduleDir)) {
    return parts.join('\n');
  }

  const collectRustFiles = (dirPath) => {
    const nestedFiles = [];
    for (const entry of fs
      .readdirSync(dirPath, { withFileTypes: true })
      .sort((left, right) => left.name.localeCompare(right.name))) {
      const entryPath = path.join(dirPath, entry.name);
      if (entry.isDirectory()) {
        nestedFiles.push(...collectRustFiles(entryPath));
        continue;
      }
      if (entry.isFile() && entry.name.endsWith('.rs')) {
        nestedFiles.push(entryPath);
      }
    }
    return nestedFiles;
  };

  for (const rustFile of collectRustFiles(moduleDir)) {
    parts.push(readText(rustFile));
  }

  return parts.join('\n');
}

function assertPattern(source, pattern, message) {
  assert(pattern.test(source), message);
}

export function verifyDesktopAuxWindowContract({ repoRoot = resolveRepoRoot() } = {}) {
  const windowSpacePath = path.join(repoRoot, 'app', 'src-tauri', 'src', 'window_space', 'mod.rs');
  const commandsPath = path.join(repoRoot, 'app', 'src-tauri', 'src', 'commands.rs');
  // Post-#3303 split: window_commands.rs became window_commands/.
  // Read every non-test sibling so the contract can find the
  // apply_auxiliary_window_space_state call wherever it lives in the
  // subtree (focus_mode.rs, popover.rs, deep_link.rs, etc.).
  const windowCommandsDir = path.join(
    repoRoot,
    'app',
    'src-tauri',
    'src',
    'commands',
    'ui',
    'window_commands',
  );
  const windowCommandsLegacyPath = path.join(
    repoRoot,
    'app',
    'src-tauri',
    'src',
    'commands',
    'ui',
    'window_commands.rs',
  );
  const desktopShellModulePath = path.join(
    repoRoot,
    'app',
    'src-tauri',
    'src',
    'desktop_shell',
    'mod.rs',
  );
  const desktopShellLegacyPath = path.join(
    repoRoot,
    'app',
    'src-tauri',
    'src',
    'desktop_shell.rs',
  );
  const windowRestorePath = path.join(repoRoot, 'app', 'src-tauri', 'src', 'window_restore.rs');

  const windowSpaceSource = readRustModuleText(windowSpacePath);
  const windowCommandsModPath = path.join(windowCommandsDir, 'mod.rs');
  const commandsSource = [
    readText(commandsPath),
    fs.existsSync(windowCommandsModPath)
      ? readRustModuleText(windowCommandsModPath)
      : fs.existsSync(windowCommandsLegacyPath)
        ? readText(windowCommandsLegacyPath)
        : '',
  ].join('\n');
  const desktopShellSource = fs.existsSync(desktopShellModulePath)
    ? readRustModuleText(desktopShellModulePath)
    : readRustModuleText(desktopShellLegacyPath);
  const windowRestoreSource = readRustModuleText(windowRestorePath);

  assertPattern(
    windowSpaceSource,
    /pub\(crate\)\s+enum\s+AuxiliaryWindowKind\s*\{[\s\S]*Popover[\s\S]*\}/,
    'window_space module tree must define AuxiliaryWindowKind with the Popover variant',
  );

  assertPattern(
    windowSpaceSource,
    /pub\(crate\)\s+enum\s+AuxiliaryWindowState\s*\{[\s\S]*Hidden[\s\S]*Presented[\s\S]*\}/,
    'window_space module tree must define AuxiliaryWindowState with Hidden and Presented variants',
  );

  assertPattern(
    windowSpaceSource,
    /pub\(crate\)\s+fn\s+apply_auxiliary_window_space_state\s*\(/,
    'window_space module tree must expose apply_auxiliary_window_space_state() as the shared desktop helper',
  );

  assertPattern(
    desktopShellSource,
    /apply_auxiliary_window_space_state\(\s*&popover,\s*AuxiliaryWindowKind::Popover,\s*AuxiliaryWindowState::Presented,\s*\)/,
    'desktop_shell module tree must route tray popover presentation through the shared auxiliary window helper',
  );

  assertPattern(
    desktopShellSource,
    /(?:hide_popover_window\(|apply_auxiliary_window_space_state\(\s*&popover,\s*AuxiliaryWindowKind::Popover,\s*AuxiliaryWindowState::Hidden,\s*\))/,
    'desktop_shell module tree must route tray popover teardown through the shared auxiliary window helper',
  );

  assertPattern(
    desktopShellSource,
    /popover\.on_window_event\([\s\S]*?CloseRequested[\s\S]*?prevent_close\(\)[\s\S]*?(?:hide_popover_window\(|apply_auxiliary_window_space_state\(\s*&popover,\s*AuxiliaryWindowKind::Popover,\s*AuxiliaryWindowState::Hidden,\s*\)[\s\S]*?popover\.hide\()/,
    'desktop_shell module tree must intercept popover close requests and route them through the canonical hide path',
  );

  assert(
    !/focus_main_window\(\s*app,\s*"tray_no_popover_window"\s*\)/.test(desktopShellSource),
    'desktop_shell module tree must not fall back to the main window when the popover handle is missing',
  );

  assertPattern(
    desktopShellSource,
    /fn\s+ensure_popover_window\s*\([\s\S]*?WebviewWindowBuilder::new\([\s\S]*?(?:"popover"|POPOVER_WINDOW_LABEL)[\s\S]*?WebviewUrl::App\(\s*(?:"index\.html#popover"|POPOVER_WINDOW_HASH_ROUTE)\.into\(\)\s*\)/,
    'desktop_shell module tree must be able to rebuild the popover window when the runtime handle is missing',
  );

  assertPattern(
    windowRestoreSource,
    /apply_auxiliary_window_space_state\(\s*&popover,\s*AuxiliaryWindowKind::Popover,\s*AuxiliaryWindowState::Hidden,\s*\)/,
    'window_restore.rs must clear popover auxiliary window policy during main-window restoration',
  );

  assert(
    !/AuxiliaryWindowKind::Focus/.test(`${windowSpaceSource}\n${commandsSource}\n${desktopShellSource}\n${windowRestoreSource}`),
    'retired focus auxiliary window policy must not be reintroduced into the desktop auxiliary window path',
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  verifyDesktopAuxWindowContract();
  console.log(`${SCRIPT_TAG} Desktop auxiliary window contract checks passed.`);
}
