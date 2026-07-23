import fs from 'node:fs';
import path from 'node:path';
import ts from 'typescript';

import { resolveCssImportGraph } from './css_graph.mjs';

export function fail(message) {
  throw new Error(`[ui_wiring] ERROR: ${message}`);
}

function readText(filePath) {
  if (!fs.existsSync(filePath)) {
    fail(`Missing file: ${filePath}`);
  }
  return fs.readFileSync(filePath, 'utf8');
}

function readLocaleCatalogFile(filePath) {
  if (!fs.existsSync(filePath)) {
    throw new Error(`[locale_catalog] ERROR: Missing file: ${filePath}`);
  }
  let data;
  try {
    data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`[locale_catalog] ERROR: Failed to parse ${filePath}: ${message}`);
  }
  if (data === null || Array.isArray(data) || typeof data !== 'object') {
    throw new Error(`[locale_catalog] ERROR: Locale catalog must be a flat object: ${filePath}`);
  }
  return data;
}

export function readLocaleCatalog(repoRoot, localeCode) {
  return readLocaleCatalogFile(path.join(repoRoot, 'app/src/locales', `${localeCode}.json`));
}

export function readStrictParityLocaleCodes(repoRoot) {
  const configPath = path.join(repoRoot, 'app/src/locales/strict-parity.json');
  if (!fs.existsSync(configPath)) {
    throw new Error(`[locale_catalog] ERROR: Missing strict-parity locale config: ${configPath}`);
  }
  let data;
  try {
    data = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`[locale_catalog] ERROR: Failed to parse ${configPath}: ${message}`);
  }
  if (!Array.isArray(data) || data.some((code) => typeof code !== 'string' || code.trim() === '')) {
    throw new Error('[locale_catalog] ERROR: strict-parity locale config must be a non-empty string array');
  }
  return Array.from(new Set(data.map((code) => code.trim())));
}

export function missingLocaleCatalogKeys(localeCatalog, keys) {
  return keys.filter((key) => typeof localeCatalog[key] !== 'string');
}

function readTreeTexts(dirPath) {
  if (!fs.existsSync(dirPath)) {
    fail(`Missing directory: ${dirPath}`);
  }

  const parts = [];
  const walk = (currentPath) => {
    const entries = fs.readdirSync(currentPath, { withFileTypes: true })
      .sort((left, right) => left.name.localeCompare(right.name));
    for (const entry of entries) {
      const fullPath = path.join(currentPath, entry.name);
      if (entry.isDirectory()) {
        walk(fullPath);
        continue;
      }
      if (/\.(?:ts|tsx|mjs)$/.test(entry.name)) {
        parts.push(readText(fullPath));
      }
    }
  };

  walk(dirPath);
  return parts.join('\n');
}

export function escapeRegex(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

export function ensurePattern(source, pattern, label) {
  if (!pattern.test(source)) {
    fail(`Missing pattern for ${label}`);
  }
}

export function ensureNoPattern(source, pattern, label) {
  if (pattern.test(source)) {
    fail(`Unexpected pattern for ${label}`);
  }
}

function createSourceFile(source) {
  return ts.createSourceFile('ui-wiring-inline.tsx', source, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
}

function unwrapInitializer(node) {
  let current = node;
  while (
    ts.isAsExpression(current)
    || ts.isSatisfiesExpression(current)
    || ts.isParenthesizedExpression(current)
    || ts.isTypeAssertionExpression(current)
  ) {
    current = current.expression;
  }
  return current;
}

function isStringLiteralNode(node) {
  return ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node);
}

function stringLiteralValue(node) {
  return isStringLiteralNode(node) ? node.text : null;
}

function findConstDeclaration(source, constName) {
  const sourceFile = createSourceFile(source);
  for (const statement of sourceFile.statements) {
    if (!ts.isVariableStatement(statement)) continue;
    for (const declaration of statement.declarationList.declarations) {
      if (!ts.isIdentifier(declaration.name) || declaration.name.text !== constName) continue;
      return declaration;
    }
  }
  return null;
}

export function extractConstStringArray(source, constName) {
  const declaration = findConstDeclaration(source, constName);
  if (!declaration?.initializer) {
    fail(`Could not find const array: ${constName}`);
  }
  const initializer = unwrapInitializer(declaration.initializer);
  if (!ts.isArrayLiteralExpression(initializer)) {
    fail(`Could not find const array: ${constName}`);
  }
  const values = initializer.elements
    .map((element) => stringLiteralValue(element))
    .filter((value) => typeof value === 'string');
  if (values.length === 0) {
    fail(`No string values found for const array: ${constName}`);
  }
  return values;
}

export function extractConstTopLevelObjectKeys(source, constName) {
  let declaration = findConstDeclaration(source, constName);
  if (!declaration?.initializer) {
    fail(`Could not find object literal: ${constName}`);
  }
  let initializer = unwrapInitializer(declaration.initializer);
  // Follow identifier aliases (e.g. `export const FOO = FOO_STATIC;`)
  // back to the underlying object literal, so a re-exported alias
  // counts as the same shape as the original literal binding.
  const visited = new Set([constName]);
  while (ts.isIdentifier(initializer) && !visited.has(initializer.text)) {
    const aliasName = initializer.text;
    visited.add(aliasName);
    const aliasDecl = findConstDeclaration(source, aliasName);
    if (!aliasDecl?.initializer) break;
    initializer = unwrapInitializer(aliasDecl.initializer);
  }
  if (!ts.isObjectLiteralExpression(initializer)) {
    fail(`Could not find object literal: ${constName}`);
  }

  const keys = [];
  for (const property of initializer.properties) {
    if (!ts.isPropertyAssignment(property)) continue;
    if (ts.isIdentifier(property.name)) {
      keys.push(property.name.text);
      continue;
    }
    const key = stringLiteralValue(property.name);
    if (key) {
      keys.push(key);
    }
  }
  if (keys.length === 0) {
    fail(`No object keys found for: ${constName}`);
  }
  return keys;
}

export function extractOptionValuesFromArray(source, constName) {
  const declaration = findConstDeclaration(source, constName);
  if (!declaration?.initializer) {
    fail(`Could not find options array: ${constName}`);
  }
  const initializer = unwrapInitializer(declaration.initializer);
  if (!ts.isArrayLiteralExpression(initializer)) {
    fail(`Could not find options array: ${constName}`);
  }
  const values = [];
  for (const element of initializer.elements) {
    const item = unwrapInitializer(element);
    if (!ts.isObjectLiteralExpression(item)) continue;
    for (const property of item.properties) {
      if (!ts.isPropertyAssignment(property)) continue;
      if (!ts.isIdentifier(property.name) || property.name.text !== 'value') continue;
      const value = stringLiteralValue(property.initializer);
      if (value) {
        values.push(value);
      }
    }
  }
  if (values.length === 0) {
    fail(`No option values found for: ${constName}`);
  }
  return values;
}

export function loadUiWiringContractSources(repoRoot) {
  const settingsViewPath = path.join(repoRoot, 'app/src/components/SettingsView.tsx');
  const appearanceSettingsDirPath = path.join(
    repoRoot,
    'app/src/components/settings/appearance',
  );
  const generalSettingsDirPath = path.join(
    repoRoot,
    'app/src/components/settings/general',
  );
  const sharedTypesPath = path.join(repoRoot, 'shared/src/types.ts');
  const themeLibPath = path.join(repoRoot, 'app/src/lib/theme.tsx');
  const themeLibDirPath = path.join(repoRoot, 'app/src/lib/theme');
  const sidebarPath = path.join(repoRoot, 'app/src/components/Sidebar.tsx');
  const sidebarDirPath = path.join(repoRoot, 'app/src/components/sidebar');
  const commandPalettePath = path.join(repoRoot, 'app/src/components/CommandPalette.tsx');
  const commandPaletteDirPath = path.join(repoRoot, 'app/src/components/command-palette');
  const calendarViewPath = path.join(repoRoot, 'app/src/components/CalendarView.tsx');
  const calendarDirPath = path.join(repoRoot, 'app/src/components/calendar');
  const todayViewPath = path.join(repoRoot, 'app/src/components/TodayView.tsx');
  const todayViewDirPath = path.join(repoRoot, 'app/src/components/today-view');
  const dailyReviewViewPath = path.join(repoRoot, 'app/src/components/DailyReviewView.tsx');
  const aiMemoryViewPath = path.join(repoRoot, 'app/src/components/ai-memory/AIMemoryView.tsx');
  const aiMemoryDirPath = path.join(repoRoot, 'app/src/components/ai-memory');
  const changelogViewPath = path.join(repoRoot, 'app/src/components/ChangelogView.tsx');
  const taskMetadataEditorDirPath = path.join(repoRoot, 'app/src/components/task-detail/metadata-editor');
  const dateLocaleLibPath = path.join(repoRoot, 'app/src/lib/dates/dateLocale.ts');
  const appPath = path.join(repoRoot, 'app/src/App.tsx');
  const appShellDirPath = path.join(repoRoot, 'app/src/app-shell');
  const enLocalePath = path.join(repoRoot, 'app/src/locales/en.json');
  const readmePath = path.join(repoRoot, 'README.md');
  const themeCssPath = path.join(repoRoot, 'app/src/index.css');

  const settingsViewSource = readText(settingsViewPath);
  const generalSettingsSectionSource = [
    readTreeTexts(appearanceSettingsDirPath),
    readTreeTexts(generalSettingsDirPath),
  ].join('\n');

  return {
    settingsViewSource,
    generalSettingsSectionSource,
    sharedTypesSource: readText(sharedTypesPath),
    themeLibSource: [readText(themeLibPath), readTreeTexts(themeLibDirPath)].join('\n'),
    sidebarSource: [readText(sidebarPath), readTreeTexts(sidebarDirPath)].join('\n'),
    commandPaletteSource: [readText(commandPalettePath), readTreeTexts(commandPaletteDirPath)].join('\n'),
    calendarViewSource: [readText(calendarViewPath), readTreeTexts(calendarDirPath)].join('\n'),
    todayViewSource: [readText(todayViewPath), readTreeTexts(todayViewDirPath)].join('\n'),
    dailyReviewViewSource: readText(dailyReviewViewPath),
    aiMemoryViewSource: [
      readText(aiMemoryViewPath),
      fs.existsSync(aiMemoryDirPath) ? readTreeTexts(aiMemoryDirPath) : '',
    ].filter(Boolean).join('\n'),
    changelogViewSource: readText(changelogViewPath),
    taskMetadataEditorSource: readTreeTexts(taskMetadataEditorDirPath),
    dateLocaleLibSource: readText(dateLocaleLibPath),
    appSource: [
      readText(appPath),
      fs.existsSync(appShellDirPath) ? readTreeTexts(appShellDirPath) : '',
    ].filter(Boolean).join('\n'),
    enLocaleCatalog: readLocaleCatalogFile(enLocalePath),
    readmeSource: readText(readmePath),
    settingsToggleSource: `${settingsViewSource}\n${generalSettingsSectionSource}`,
    themeCssSource: resolveCssImportGraph(themeCssPath),
  };
}
