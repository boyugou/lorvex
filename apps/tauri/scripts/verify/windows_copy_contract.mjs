#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import ts from 'typescript';
import { fileURLToPath } from 'node:url';
import {
  assertContract,
  resolveRepoRootFromMeta,
  runVerifierCli,
} from '../lib/verifier_runtime.mjs';

const SCRIPT_TAG = '[verify:windows-copy-contract]';

function readRequiredFile(filePath) {
  assertContract(fs.existsSync(filePath), SCRIPT_TAG, `missing required file: ${filePath}`);
  return fs.readFileSync(filePath, 'utf8');
}

function parseTypeScriptSource(filePath, source, scriptKind) {
  return ts.createSourceFile(filePath, source, ts.ScriptTarget.Latest, true, scriptKind);
}

function walk(node, visitor) {
  visitor(node);
  ts.forEachChild(node, (child) => walk(child, visitor));
}

function collectStringLiterals(sourceFile) {
  const values = [];
  walk(sourceFile, (node) => {
    if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) {
      values.push(node.text);
    }
  });
  return values;
}

function hasInterfaceProperty(sourceFile, propertyName) {
  let found = false;
  walk(sourceFile, (node) => {
    if (found || !ts.isPropertySignature(node) || !node.name) return;
    if (ts.isIdentifier(node.name) && node.name.text === propertyName) {
      found = true;
      return;
    }
    if (ts.isStringLiteral(node.name) && node.name.text === propertyName) {
      found = true;
    }
  });
  return found;
}

function hasCallExpressionByIdentifier(sourceFile, functionName, firstArgIdentifierName) {
  let found = false;
  walk(sourceFile, (node) => {
    if (found || !ts.isCallExpression(node)) return;
    if (!ts.isIdentifier(node.expression) || node.expression.text !== functionName) return;
    const [firstArg] = node.arguments;
    if (!firstArg || !ts.isIdentifier(firstArg) || firstArg.text !== firstArgIdentifierName) return;
    found = true;
  });
  return found;
}

function hasTrayPresentationSignal(sourceFile) {
  let found = false;
  walk(sourceFile, (node) => {
    if (found) return;
    if (ts.isIdentifier(node) && node.text === 'trayPresentationKind') {
      found = true;
      return;
    }
    if (
      ts.isPropertyAccessExpression(node)
      && ts.isIdentifier(node.name)
      && node.name.text === 'trayPresentationKind'
    ) {
      found = true;
    }
  });
  return found;
}

function readLocaleJson(filePath) {
  const source = readRequiredFile(filePath);
  let parsed;
  try {
    parsed = JSON.parse(source);
  } catch (error) {
    assertContract(false, SCRIPT_TAG, `failed to parse locale JSON ${filePath}: ${error.message}`);
  }
  assertContract(
    parsed && typeof parsed === 'object' && !Array.isArray(parsed),
    SCRIPT_TAG,
    `locale JSON ${filePath} must be a flat object`,
  );
  return parsed;
}

function readStrictParityLocaleCatalogs(repoRoot) {
  const localesRoot = path.join(repoRoot, 'app', 'src', 'locales');
  const strictParityPath = path.join(localesRoot, 'strict-parity.json');
  const localeCodes = JSON.parse(readRequiredFile(strictParityPath));
  assertContract(
    Array.isArray(localeCodes) && localeCodes.every((code) => typeof code === 'string' && code.trim()),
    SCRIPT_TAG,
    'strict-parity.json must be a non-empty JSON array of locale codes',
  );
  return localeCodes.map((localeCode) => [
    `${localeCode}.json`,
    readLocaleJson(path.join(localesRoot, `${localeCode}.json`)),
  ]);
}

function hasLocaleJsonKey(localeJson, key) {
  return Object.prototype.hasOwnProperty.call(localeJson, key);
}

function expressionContainsStringLiteral(node, expected) {
  let found = false;
  walk(node, (current) => {
    if (found) return;
    if (
      (ts.isStringLiteral(current) || ts.isNoSubstitutionTemplateLiteral(current))
      && current.text === expected
    ) {
      found = true;
    }
  });
  return found;
}

function hasToastErrorHardcodedMenuBarRollback(sourceFile) {
  let found = false;
  walk(sourceFile, (node) => {
    if (found || !ts.isCallExpression(node)) return;
    if (!ts.isPropertyAccessExpression(node.expression)) return;
    if (!ts.isIdentifier(node.expression.expression) || node.expression.expression.text !== 'toast') return;
    if (node.expression.name.text !== 'error') return;
    if (node.arguments.some((arg) => expressionContainsStringLiteral(arg, 'settings.menuBarToggleRollback'))) {
      found = true;
    }
  });
  return found;
}

export function verifyWindowsCopyContract({
  repoRoot = resolveRepoRootFromMeta(import.meta.url),
} = {}) {
  const generalTypesPath = path.join(
    repoRoot,
    'app',
    'src',
    'components',
    'settings',
    'general',
    'types.ts',
  );
  const desktopBehaviorPanelPath = path.join(
    repoRoot,
    'app',
    'src',
    'components',
    'settings',
    'general',
    'DesktopBehaviorPanel.tsx',
  );
  const settingsViewPath = path.join(repoRoot, 'app', 'src', 'components', 'SettingsView.tsx');
  const generalControllerPath = path.join(
    repoRoot,
    'app',
    'src',
    'components',
    'settings',
    'controller',
    'general',
    'runtime.ts',
  );
  const generalTypesSource = readRequiredFile(generalTypesPath);
  const desktopBehaviorPanelSource = readRequiredFile(desktopBehaviorPanelPath);
  const settingsSource = readRequiredFile(settingsViewPath);
  const generalControllerSource = readRequiredFile(generalControllerPath);
  // Locales were migrated from TS modules to flat JSON catalogs in #3328;
  // `app/src/locales/<lang>.json` is the source of truth, while `<lang>.ts`
  // files (when present) are codegen output. Verifiers must read the current
  // strict-parity catalog set instead of baking in a two-locale assumption.
  const strictParityLocaleCatalogs = readStrictParityLocaleCatalogs(repoRoot);

  const generalTypesSourceFile = parseTypeScriptSource(generalTypesPath, generalTypesSource, ts.ScriptKind.TS);
  const desktopBehaviorPanelSourceFile = parseTypeScriptSource(
    desktopBehaviorPanelPath,
    desktopBehaviorPanelSource,
    ts.ScriptKind.TSX,
  );
  const settingsSourceFile = parseTypeScriptSource(settingsViewPath, settingsSource, ts.ScriptKind.TSX);
  const generalControllerSourceFile = parseTypeScriptSource(
    generalControllerPath,
    generalControllerSource,
    ts.ScriptKind.TS,
  );

  const trayPropNames = [
    'trayIconTitleKey',
    'trayIconDescKey',
    'trayIconVisibleKey',
    'trayIconHiddenKey',
  ];
  for (const propName of trayPropNames) {
    assertContract(
      hasInterfaceProperty(generalTypesSourceFile, propName),
      SCRIPT_TAG,
      `general settings types missing prop ${propName}`,
    );
  }

  for (const propName of trayPropNames) {
    assertContract(
      hasCallExpressionByIdentifier(desktopBehaviorPanelSourceFile, 't', propName),
      SCRIPT_TAG,
      `DesktopBehaviorPanel must use ${propName}`,
    );
  }

  const generalStringLiterals = collectStringLiterals(desktopBehaviorPanelSourceFile);
  const bannedGeneralAssumptions = [
    'settings.menuBarIcon',
    'settings.menuBarIconDesc',
    'settings.menuBarIconVisible',
    'settings.menuBarIconHidden',
  ];
  for (const banned of bannedGeneralAssumptions) {
    assertContract(
      !generalStringLiterals.includes(banned),
      SCRIPT_TAG,
      `DesktopBehaviorPanel still hardcodes menu bar key: ${banned}`,
    );
  }

  assertContract(
    hasTrayPresentationSignal(settingsSourceFile),
    SCRIPT_TAG,
    'SettingsView must use trayPresentationKind semantics to select menu-bar vs system-tray copy',
  );

  assertContract(
    !hasToastErrorHardcodedMenuBarRollback(settingsSourceFile),
    SCRIPT_TAG,
    'SettingsView must not hardcode menu bar rollback toast key',
  );

  const requiredGeneralControllerLiterals = [
    'settings.menuBarIcon',
    'settings.systemTrayIcon',
    'settings.menuBarToggleRollback',
    'settings.systemTrayToggleRollback',
  ];
  const generalControllerStringLiterals = collectStringLiterals(generalControllerSourceFile);
  for (const requiredLiteral of requiredGeneralControllerLiterals) {
    assertContract(
      generalControllerStringLiterals.includes(requiredLiteral),
      SCRIPT_TAG,
      `general settings runtime helpers must include ${requiredLiteral} copy key`,
    );
  }

  assertContract(
    !hasToastErrorHardcodedMenuBarRollback(generalControllerSourceFile),
    SCRIPT_TAG,
    'general settings runtime helpers must not hardcode menu bar rollback toast key',
  );

  const requiredLocaleKeys = [
    'settings.menuBarIcon',
    'settings.menuBarIconDesc',
    'settings.menuBarIconVisible',
    'settings.menuBarIconHidden',
    'settings.menuBarToggleRollback',
    'settings.systemTrayIcon',
    'settings.systemTrayIconDesc',
    'settings.systemTrayIconVisible',
    'settings.systemTrayIconHidden',
    'settings.systemTrayToggleRollback',
  ];

  for (const [localeName, localeJson] of strictParityLocaleCatalogs) {
    for (const key of requiredLocaleKeys) {
      assertContract(
        hasLocaleJsonKey(localeJson, key),
        SCRIPT_TAG,
        `${localeName} missing required key: ${key}`,
      );
    }
  }

  return { ok: true };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runVerifierCli({
    scriptTag: SCRIPT_TAG,
    successMessage: 'Windows copy contract checks passed.',
    run: () => verifyWindowsCopyContract(),
  });
}
