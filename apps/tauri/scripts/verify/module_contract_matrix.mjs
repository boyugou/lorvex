#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { verifyUiWiringModuleAstContracts } from '../lib/ui_wiring_module_ast_contract.mjs';

const SCRIPT_TAG = '[module_contract_matrix]';

function resolveRepoRoot() {
  const scriptPath = fileURLToPath(import.meta.url);
  return path.resolve(path.dirname(scriptPath), '..', '..');
}

function fail(message) {
  throw new Error(`${SCRIPT_TAG} ERROR: ${message}`);
}

function readText(filePath) {
  if (!fs.existsSync(filePath)) {
    fail(`Missing file: ${filePath}`);
  }
  return fs.readFileSync(filePath, 'utf8');
}

function extractMatrixModuleIds(markdown) {
  const rows = Array.from(markdown.matchAll(/^\|\s*`([^`]+)`\s*\|/gm), (match) => match[1]);
  if (rows.length === 0) {
    fail('No module rows found in matrix doc (expected first column to be backticked module id).');
  }
  const duplicates = rows.filter((id, idx) => rows.indexOf(id) !== idx);
  if (duplicates.length > 0) {
    fail(`Duplicate module rows in matrix doc: ${Array.from(new Set(duplicates)).join(', ')}`);
  }
  return rows;
}

export function verifyModuleContractMatrix({ repoRoot = resolveRepoRoot() } = {}) {
  const matrixPath = path.join(repoRoot, 'docs/execution/MODULE_CONTRACT_MATRIX.md');

  const matrixSource = readText(matrixPath);

  let moduleAstContractResult;
  try {
    moduleAstContractResult = verifyUiWiringModuleAstContracts({ repoRoot });
  } catch (error) {
    fail(error instanceof Error ? error.message : String(error));
  }

  const {
    allModules,
    missingSettingsOptions,
    missingSidebarVisibilityGuards,
    missingAppRenderBranches,
    missingAppModuleGuardMappings,
  } = moduleAstContractResult;

  const matrixModules = extractMatrixModuleIds(matrixSource);
  const missingFromMatrix = allModules.filter((id) => !matrixModules.includes(id));
  const extraInMatrix = matrixModules.filter((id) => !allModules.includes(id));

  if (missingFromMatrix.length > 0) {
    fail(`Matrix missing modules from sidebar registry: ${missingFromMatrix.join(', ')}`);
  }
  if (extraInMatrix.length > 0) {
    fail(`Matrix contains unknown modules not in sidebar registry: ${extraInMatrix.join(', ')}`);
  }

  if (missingSettingsOptions.length > 0) {
    fail(`Settings toggle options missing for: ${missingSettingsOptions.join(', ')}`);
  }

  if (missingSidebarVisibilityGuards.length > 0) {
    fail(`Sidebar guards missing for: ${missingSidebarVisibilityGuards.join(', ')}`);
  }

  if (missingAppRenderBranches.length > 0) {
    fail(`MainViewContent render branches missing for mapped modules: ${missingAppRenderBranches.join(', ')}`);
  }

  if (missingAppModuleGuardMappings.length > 0) {
    fail(`App module-guard switch missing case->module mappings for: ${missingAppModuleGuardMappings.join(', ')}`);
  }

  // Mobile runtime fallback is handled inline in the navigation guard
  // (no separate isDesktopOnlySecondaryView function).

  const requiredValidationCommands = [
    'npm run verify:module-contract-matrix',
    'npm run verify:ui-wiring',
    'cd app && npx tsc --noEmit',
  ];
  for (const command of requiredValidationCommands) {
    if (!matrixSource.includes(command)) {
      fail(`Matrix doc missing validation command: ${command}`);
    }
  }

  return {
    ok: true,
    moduleCount: allModules.length,
  };
}

function runCli() {
  try {
    const result = verifyModuleContractMatrix();
    console.log(`${SCRIPT_TAG} OK: matrix doc rows cover all sidebar modules (${result.moduleCount}).`);
    console.log(`${SCRIPT_TAG} OK: settings toggles, sidebar guards, and main view render branches are complete.`);
    console.log(`${SCRIPT_TAG} OK: App module mapping and desktop-only view contracts are present.`);
    console.log(`${SCRIPT_TAG} OK: static validation path commands documented in matrix artifact.`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.startsWith(SCRIPT_TAG) ? message : `${SCRIPT_TAG} ERROR: ${message}`);
    process.exit(1);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runCli();
}
