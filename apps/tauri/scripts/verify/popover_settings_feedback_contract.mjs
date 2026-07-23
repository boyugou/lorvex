#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  missingLocaleCatalogKeys,
  readLocaleCatalog,
  readStrictParityLocaleCodes,
} from '../lib/ui_wiring_contract_support.mjs';
import { readSourceTree } from '../lib/verifier_runtime.mjs';

function fail(message) {
  console.error(`[verify:popover-settings-feedback-contract] ${message}`);
  process.exit(1);
}

function readText(filePath) {
  if (!fs.existsSync(filePath)) {
    fail(`Missing file: ${filePath}`);
  }
  return fs.readFileSync(filePath, 'utf8');
}

function readTypeScriptTree(rootPath) {
  if (!fs.existsSync(rootPath)) {
    fail(`Missing file: ${rootPath}`);
  }
  return readSourceTree(rootPath);
}

function ensurePattern(source, pattern, message) {
  if (!pattern.test(source)) {
    fail(message);
  }
}

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), '..', '..');

const popoverPath = path.join(repoRoot, 'app', 'src', 'components', 'PopoverWindow.tsx');
const popoverControllerPath = path.join(
  repoRoot,
  'app',
  'src',
  'components',
  'popover-window',
  'usePopoverWindowController.ts',
);
const popoverContentPath = path.join(
  repoRoot,
  'app',
  'src',
  'components',
  'popover-window',
  'PopoverWindowContent.tsx',
);
const settingsViewPath = path.join(repoRoot, 'app', 'src', 'components', 'SettingsView.tsx');
const dataControllerPath = path.join(
  repoRoot,
  'app',
  'src',
  'components',
  'settings',
  'controller',
  'useDataSettingsController.ts',
);
const dataDiagnosticsPath = path.join(
  repoRoot,
  'app',
  'src',
  'components',
  'settings',
  'controller',
  'data',
  'diagnostics.ts',
);
const dataDiagnosticsTreePath = path.join(
  repoRoot,
  'app',
  'src',
  'components',
  'settings',
  'controller',
  'data',
  'diagnostics',
);
const diagnosticsPanelPath = path.join(
  repoRoot,
  'app',
  'src',
  'components',
  'settings',
  'data',
  'DiagnosticsPanel.tsx',
);
const diagnosticsPanelTreePath = path.join(
  repoRoot,
  'app',
  'src',
  'components',
  'settings',
  'data',
  'diagnostics-panel',
);

const popoverSource = readText(popoverPath);
const popoverControllerSource = `${readText(popoverControllerPath)}\n${readTypeScriptTree(path.join(
  repoRoot,
  'app',
  'src',
  'components',
  'popover-window',
  'controller',
))}`;
const popoverContentSource = readText(popoverContentPath);
const settingsViewSource = readText(settingsViewPath);
const dataControllerSource = `${readText(dataControllerPath)}\n${readText(dataDiagnosticsPath)}\n${readTypeScriptTree(dataDiagnosticsTreePath)}`;
const diagnosticsPanelSource = `${readText(diagnosticsPanelPath)}\n${readTypeScriptTree(diagnosticsPanelTreePath)}`;
const strictLocaleCatalogs = readStrictParityLocaleCodes(repoRoot).map((localeCode) => [
  localeCode,
  readLocaleCatalog(repoRoot, localeCode),
]);

ensurePattern(
  popoverControllerSource,
  /const attentionCount = overview\?\.stats\.attention_count \?\? 0;/,
  'PopoverWindow must read canonical attention_count instead of recomputing overdue + today_pool locally.',
);

// Header now uses the i18n-pluralization helper
// `formatPopoverTasksInPlanCountLabel` (which internally pulls the
// `popover.tasksInPlanCount.*` key family) instead of inlining the
// bare `popover.tasksInPlan` key. The structural intent — the header
// renders `attentionCount` together with the "tasks in plan" label —
// is preserved by either form.
ensurePattern(
  popoverContentSource,
  /(?:\{attentionCount\}[\s\S]*popover\.tasksInPlan|formatPopoverTasksInPlanCountLabel\([^)]*attentionCount)/,
  'PopoverWindow must render attentionCount alongside the "tasks in plan" label in the header stats area.',
);

ensurePattern(
  popoverControllerSource,
  /loadSummaryRequestIdRef/,
  'PopoverWindow must track summary request ids so stale refreshes cannot overwrite newer popover state.',
);

ensurePattern(
  popoverControllerSource,
  /await Promise\.allSettled\(\[[\s\S]*?getOverview\(\),[\s\S]*?getCurrentFocus\(\)/,
  'PopoverWindow must use Promise.allSettled() so one failed summary source does not block the others.',
);

ensurePattern(
  popoverControllerSource,
  /if \([^)]*requestId !== loadSummaryRequestIdRef\.current[^)]*\) return;/,
  'PopoverWindow must ignore stale summary responses when a newer refresh is already in flight.',
);

ensurePattern(
  popoverControllerSource,
  /popover\.loadOverview/,
  'PopoverWindow must log overview refresh failures distinctly.',
);

ensurePattern(
  popoverControllerSource,
  /popover\.loadCurrentFocus/,
  'PopoverWindow must log daily-plan refresh failures distinctly.',
);

// `handleRefreshErrorLogs` was decomposed out of
// `useDataSettingsController` into `data/diagnostics/actions.ts` and
// took a default `announce = true` parameter so the same callback
// can serve both manual-refresh ("announce") and post-clear ("don't
// double-toast") flows. The structural intent is unchanged: the
// callback forwards to `refreshErrorLogs(false, <announce>)` so the
// manual refresh path always emits explicit feedback.
ensurePattern(
  dataControllerSource,
  /const handleRefreshErrorLogs = useCallback\(async \((?:\)|announce(?:\s*=\s*true)?\))\s*=> \{\s*await refreshErrorLogs\(false,\s*(?:true|announce)\);\s*}, \[refreshErrorLogs\]\);/s,
  'useDataSettingsController must provide explicit refresh feedback via handleRefreshErrorLogs().',
);

ensurePattern(
  dataControllerSource,
  /await refreshErrorLogs\(true, true\);/,
  'useDataSettingsController clear-error-log flow must refresh merged diagnostics after delete.',
);

ensurePattern(
  diagnosticsPanelSource,
  /t\('settings\.errorLogsScopeHint'\)/,
  'DiagnosticsPanel must explain clear scope to avoid click-no-effect confusion.',
);

for (const [localeCode, catalog] of strictLocaleCatalogs) {
  const missing = missingLocaleCatalogKeys(catalog, ['settings.errorLogsScopeHint']);
  if (missing.length > 0) {
    fail(`${localeCode} strict-parity locale must include settings.errorLogsScopeHint copy: missing ${missing.join(', ')}`);
  }
}

console.log('[verify:popover-settings-feedback-contract] Popover + Settings feedback contract checks passed.');
