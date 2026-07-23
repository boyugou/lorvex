import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { resolveCssImportGraph } from '../../lib/css_graph.mjs';
import { repoRoot } from './shared.mjs';

function readQuotedValuesFromTsArray(source, constName) {
  const pattern = new RegExp(`const ${constName}:.*?= \\[([\\s\\S]*?)\\];`);
  const match = source.match(pattern);
  assert.ok(match, `Expected ${constName} array in source`);
  return Array.from(match[1].matchAll(/value:\s*'([^']+)'/g), (item) => item[1]);
}

function readQuotedValuesFromSharedArray(source, constName) {
  const pattern = new RegExp(`export const ${constName} = \\[([\\s\\S]*?)\\] as const;`);
  const match = source.match(pattern);
  assert.ok(match, `Expected ${constName} array in shared source`);
  return Array.from(match[1].matchAll(/'([^']+)'/g), (item) => item[1]);
}

function readUtilityBlocks(source) {
  const blocks = [];
  const pattern = /@utility\s+([^{\s]+)[^{]*\{/g;
  let match;

  while ((match = pattern.exec(source)) !== null) {
    let depth = 1;
    let index = pattern.lastIndex;
    for (; index < source.length && depth > 0; index += 1) {
      const char = source[index];
      if (char === '{') depth += 1;
      if (char === '}') depth -= 1;
    }
    blocks.push({
      name: match[1],
      body: source.slice(pattern.lastIndex, index - 1),
    });
    pattern.lastIndex = index;
  }

  return blocks;
}

function readFilesRecursively(dir, predicate) {
  const files = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...readFilesRecursively(fullPath, predicate));
      continue;
    }
    if (predicate(fullPath)) files.push(fullPath);
  }
  return files;
}

test('app theme option registry stays aligned with shared theme modes', () => {
  const sharedTypes = fs.readFileSync(path.join(repoRoot, 'shared/src/types.ts'), 'utf8');
  const themeSource = fs.readFileSync(path.join(repoRoot, 'app/src/lib/theme/model.ts'), 'utf8');

  const sharedThemeModes = readQuotedValuesFromSharedArray(sharedTypes, 'THEME_MODES');
  const appThemeOptions = readQuotedValuesFromTsArray(themeSource, 'baseThemeOptions');

  assert.deepEqual(
    appThemeOptions,
    sharedThemeModes,
    'app baseThemeOptions should match shared THEME_MODES exactly',
  );
});

test('app appearance profile registry stays aligned with shared appearance profiles', () => {
  const sharedTypes = fs.readFileSync(path.join(repoRoot, 'shared/src/types.ts'), 'utf8');
  const themeSource = fs.readFileSync(path.join(repoRoot, 'app/src/lib/theme/model.ts'), 'utf8');

  const sharedAppearanceProfiles = readQuotedValuesFromSharedArray(sharedTypes, 'APPEARANCE_PROFILES');
  const appAppearanceProfiles = readQuotedValuesFromTsArray(themeSource, 'baseAppearanceProfileOptions');

  assert.deepEqual(
    appAppearanceProfiles,
    sharedAppearanceProfiles,
    'app baseAppearanceProfileOptions should match shared APPEARANCE_PROFILES exactly',
  );
});

test('theme token verifier accepts profile-only clarity override defaults outside theme blocks', () => {
  const result = spawnSync(process.execPath, ['scripts/verify/theme_tokens.mjs'], {
    cwd: repoRoot,
    encoding: 'utf8',
  });

  assert.equal(
    result.status,
    0,
    [
      'theme token verifier should not require --clarity-override-* values in each concrete theme',
      result.stdout,
      result.stderr,
    ].filter(Boolean).join('\n'),
  );
});

test('appearance profile controls only use existing theme utility classes', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/appearance/AppearanceSettingsSection.tsx'),
    'utf8',
  );

  assert.doesNotMatch(source, /bg-accent-soft/);
  assert.doesNotMatch(source, /hover:text-text(?:\s|['"`])/);
});

test('mobile More sheet uses theme overlay token for its modal scrim', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/app-shell/main-window/MobileMainWindow.tsx'),
    'utf8',
  );

  assert.doesNotMatch(source, /backdropClassName="bg-black\/40\b/);
  assert.match(
    source,
    /backdropClassName="bg-\[var\(--color-overlay\)\] animate-\[fade-in_0\.12s_ease-out\]"/,
  );
});

test('theme stylesheet does not declare empty Tailwind utilities', () => {
  const source = resolveCssImportGraph(path.join(repoRoot, 'app/src/index.css'));
  const emptyUtilities = readUtilityBlocks(source)
    .filter(({ body }) => body.replace(/\/\*[\s\S]*?\*\//g, '').trim().length === 0)
    .map(({ name }) => name);

  assert.deepEqual(emptyUtilities, [], 'empty @utility blocks make Tailwind/Vite fail at serve time');
});

test('CSS import graph exposes stylesheet module content to contracts', () => {
  const source = resolveCssImportGraph(path.join(repoRoot, 'app/src/index.css'));

  assert.match(source, /@utility\s+desktop-shell\s*\{/);
  assert.match(source, /:root\[data-theme='liquid'\]\s+\.liquid-sidebar-shell\.profile-material-shell/);
  assert.match(source, /\.markdown-content\s+h1,\s*\n\s*\.milkdown-editor-wrapper \.ProseMirror h1/);
});

test('global stylesheet entrypoint stays an import-only root', () => {
  const source = fs.readFileSync(path.join(repoRoot, 'app/src/index.css'), 'utf8');
  const significantLines = source
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);

  assert.ok(
    significantLines.length <= 32,
    `app/src/index.css should stay an import root, but has ${significantLines.length} non-empty lines`,
  );
  assert.equal(significantLines[0], "@import 'tailwindcss';");

  const moduleImports = significantLines.slice(1);
  assert.ok(moduleImports.length >= 6, 'app/src/index.css should import owned CSS modules');
  assert.ok(
    moduleImports.every((line) => /^@import '\.\/styles\/[a-z0-9-]+\.css';$/.test(line)),
    'app/src/index.css should only import app/src/styles/*.css modules after tailwindcss',
  );
});

test('app source comments do not contain placeholder Tailwind arbitrary classes', () => {
  const appSourceFiles = readFilesRecursively(
    path.join(repoRoot, 'app/src'),
    (file) => /\.(?:css|tsx?|jsx?)$/.test(file),
  );
  const offenders = [];
  for (const file of appSourceFiles) {
    const source = fs.readFileSync(file, 'utf8');
    if (/(?:^|[\s`'"])(?:[\w-]+:)*bg-\[var\(--\{[^)]+\)\]/.test(source)) {
      offenders.push(path.relative(repoRoot, file));
    }
  }

  assert.deepEqual(
    offenders,
    [],
    'placeholder examples like bg-[var(--{tone}-tint-sm)] are scanned as real Tailwind classes',
  );
});

test('app components use the small typography tokens instead of raw 10px or 11px utilities', () => {
  const appSourceFiles = readFilesRecursively(
    path.join(repoRoot, 'app/src'),
    (file) => /\.(?:tsx?|jsx?)$/.test(file) && !/\.test\./.test(file),
  );
  const offenders = [];

  for (const file of appSourceFiles) {
    const source = fs.readFileSync(file, 'utf8');
    if (/\btext-\[(?:10|11)px\]/.test(source)) {
      offenders.push(path.relative(repoRoot, file));
    }
  }

  assert.deepEqual(
    offenders,
    [],
    'use text-3xs/text-2xs tokens so microcopy follows the theme typography scale',
  );
});
