#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { resolveCssImportGraph } from '../lib/css_graph.mjs';

function failAndExit(message) {
  console.error(`[theme_tokens] ERROR: ${message}`);
  process.exit(1);
}

function readFileOrFail(absolutePath, displayPath) {
  if (!fs.existsSync(absolutePath)) {
    failAndExit(`Missing required file: ${displayPath}`);
  }

  const stats = fs.statSync(absolutePath);
  if (stats.isDirectory()) {
    return fs
      .readdirSync(absolutePath, { withFileTypes: true })
      .sort((left, right) => left.name.localeCompare(right.name))
      .map((entry) => readFileOrFail(path.join(absolutePath, entry.name), `${displayPath}/${entry.name}`))
      .join('\n');
  }

  return fs.readFileSync(absolutePath, 'utf8');
}

function extractConstStringArray(typesSource, constName) {
  const constMatch = typesSource.match(new RegExp(`export const ${constName}\\s*=\\s*\\[(.*?)\\]\\s*as const\\s*;`, 's'));
  if (!constMatch) {
    failAndExit(`Could not find ${constName} declaration in shared/src/types.ts`);
  }

  const values = Array.from(constMatch[1].matchAll(/(['"])([^'"\n]+)\1/g), (match) => match[2]);
  if (values.length === 0) {
    failAndExit(`${constName} declaration is empty in shared/src/types.ts`);
  }
  return values;
}

function extractThemeModes(typesSource) {
  const values = extractConstStringArray(typesSource, 'THEME_MODES');

  const concreteThemes = values.filter((theme) => theme !== 'system');
  if (concreteThemes.length === 0) {
    failAndExit('No concrete themes found in THEME_MODES after excluding "system"');
  }

  return concreteThemes;
}

function skipQuotedString(source, startIndex) {
  const quote = source[startIndex];
  let index = startIndex + 1;

  while (index < source.length) {
    if (source[index] === '\\') {
      index += 2;
      continue;
    }

    if (source[index] === quote) {
      return index;
    }

    index += 1;
  }

  return source.length - 1;
}

function parseTopLevelBlocks(source) {
  const blocks = [];
  let depth = 0;
  let regionStart = 0;
  let blockStart = -1;
  let selector = '';

  for (let i = 0; i < source.length; i += 1) {
    const char = source[i];

    if (char === '"' || char === "'") {
      i = skipQuotedString(source, i);
      continue;
    }

    if (char === '{') {
      if (depth === 0) {
        selector = source.slice(regionStart, i).trim();
        blockStart = i;
      }
      depth += 1;
      continue;
    }

    if (char === '}') {
      if (depth === 0) {
        continue;
      }

      depth -= 1;
      if (depth === 0) {
        const body = source.slice(blockStart + 1, i);
        blocks.push({ selector, body });
        regionStart = i + 1;
      }
    }
  }

  return blocks;
}

function collectBlocksRecursively(source, collected = []) {
  const blocks = parseTopLevelBlocks(source);

  for (const block of blocks) {
    collected.push(block);
    collectBlocksRecursively(block.body, collected);
  }

  return collected;
}

function splitSelectorList(selector) {
  return selector
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean);
}

function normalizeSelector(selector) {
  return selector.replace(/\s+/g, '').replaceAll('"', "'");
}

function extractCssVariables(source) {
  const variableMatches = source.matchAll(/(--[a-zA-Z0-9_-]+)\s*:/g);
  return new Set(Array.from(variableMatches, (match) => match[1]));
}

function ensureFileContains(filePath, pattern, errorMessage) {
  const source = readFileOrFail(filePath, path.relative(repoRoot, filePath));
  if (!pattern.test(source)) {
    failAndExit(errorMessage);
  }
}

function ensureSourceContains(source, pattern, errorMessage) {
  if (!pattern.test(source)) {
    failAndExit(errorMessage);
  }
}

function findSemanticRootBlock(cssBlocks) {
  const semanticThemeAnchors = [
    '--color-surface-0',
    '--color-accent',
    '--desktop-shell-top-tint',
  ];

  return cssBlocks.find((block) => {
    const selectorEntries = splitSelectorList(block.selector).map(normalizeSelector);
    const variables = extractCssVariables(block.body);
    return selectorEntries.includes(':root') && semanticThemeAnchors.every((variable) => variables.has(variable));
  });
}

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), '..', '..');
const typesPath = path.join(repoRoot, 'shared/src/types.ts');
const cssPath = path.join(repoRoot, 'app/src/index.css');

const typesSource = readFileOrFail(typesPath, 'shared/src/types.ts');
readFileOrFail(cssPath, 'app/src/index.css');
const cssSource = resolveCssImportGraph(cssPath);

const concreteThemes = extractThemeModes(typesSource);
const appearanceProfiles = extractConstStringArray(typesSource, 'APPEARANCE_PROFILES');
const cssWithoutComments = cssSource.replace(/\/\*[\s\S]*?\*\//g, '');
const cssBlocks = collectBlocksRecursively(cssWithoutComments);

const semanticRootBlock = findSemanticRootBlock(cssBlocks);
if (!semanticRootBlock) {
  failAndExit('Could not find canonical semantic :root theme-token block in app/src/index.css');
}

const requiredVariables = Array.from(extractCssVariables(semanticRootBlock.body)).sort();
if (requiredVariables.length === 0) {
  failAndExit('Canonical semantic :root theme-token block does not define any CSS variables');
}

const errors = [];
const missingThemeBlocks = [];

for (const theme of concreteThemes) {
  const expectedSelector = `:root[data-theme='${theme}']`;

  const matchingThemeBlocks = cssBlocks.filter((block) => {
    const selectorEntries = splitSelectorList(block.selector).map(normalizeSelector);
    return selectorEntries.includes(expectedSelector);
  });

  if (matchingThemeBlocks.length === 0) {
    missingThemeBlocks.push(theme);
    continue;
  }

  const themeVariables = new Set();
  for (const block of matchingThemeBlocks) {
    for (const variable of extractCssVariables(block.body)) {
      themeVariables.add(variable);
    }
  }

  const missingVariables = requiredVariables.filter((variable) => !themeVariables.has(variable));
  if (missingVariables.length > 0) {
    errors.push(
      `Theme '${theme}' is missing ${missingVariables.length} required CSS variable(s): ${missingVariables.join(', ')}`,
    );
  }
}

if (missingThemeBlocks.length > 0) {
  errors.unshift(
    `Missing theme block(s) in app/src/index.css: ${missingThemeBlocks.join(', ')}`,
  );
}

const profileErrors = [];
const missingProfileBlocks = [];
const requiredProfileSelector = ":root[data-appearance-profile='clarity']";
const requiredProfileBlock = cssBlocks.find((block) => {
  const selectorEntries = splitSelectorList(block.selector).map(normalizeSelector);
  return selectorEntries.includes(requiredProfileSelector);
});
if (!requiredProfileBlock) {
  profileErrors.push(`Missing canonical appearance profile block: ${requiredProfileSelector}`);
} else {
  const requiredProfileVariables = Array.from(extractCssVariables(requiredProfileBlock.body)).sort();
  if (requiredProfileVariables.length === 0) {
    profileErrors.push(`Canonical appearance profile block '${requiredProfileSelector}' has no CSS variables`);
  } else {
    for (const profile of appearanceProfiles) {
      const expectedSelector = `:root[data-appearance-profile='${profile}']`;
      const matchingProfileBlocks = cssBlocks.filter((block) => {
        const selectorEntries = splitSelectorList(block.selector).map(normalizeSelector);
        return selectorEntries.includes(expectedSelector);
      });
      if (matchingProfileBlocks.length === 0) {
        missingProfileBlocks.push(profile);
        continue;
      }

      const profileVariables = new Set();
      for (const block of matchingProfileBlocks) {
        for (const variable of extractCssVariables(block.body)) {
          profileVariables.add(variable);
        }
      }

      const missingVariables = requiredProfileVariables.filter((variable) => !profileVariables.has(variable));
      if (missingVariables.length > 0) {
        profileErrors.push(
          `Appearance profile '${profile}' is missing ${missingVariables.length} required CSS variable(s): ${missingVariables.join(', ')}`,
        );
      }
    }
  }
}

if (missingProfileBlocks.length > 0) {
  profileErrors.unshift(
    `Missing appearance profile block(s) in app/src/index.css: ${missingProfileBlocks.join(', ')}`,
  );
}

for (const message of profileErrors) {
  errors.push(message);
}

if (errors.length > 0) {
  for (const message of errors) {
    console.error(`[theme_tokens] ERROR: ${message}`);
  }
  process.exit(1);
}

ensureFileContains(
  path.join(repoRoot, 'app/src/components/sidebar/SidebarContent.tsx'),
  /\bprofile-material-shell\b/,
  "Sidebar must include 'profile-material-shell' class for bounded material treatment.",
);
ensureFileContains(
  path.join(repoRoot, 'app/src/components/settings/SettingsPrimitives.tsx'),
  /\bprofile-material-panel\b/,
  "Settings panels must include 'profile-material-panel' class for bounded material treatment.",
);
ensureFileContains(
  path.join(repoRoot, 'app/src/components/popover-window/PopoverWindowContent.tsx'),
  /\bprofile-material-panel\b/,
  "Popover panel must include 'profile-material-panel' class for bounded material treatment.",
);
// The liquid sidebar-shell/profile-material-shell composition is a regular
// selector because the shared body lives outside either single utility.
ensureSourceContains(
  cssSource,
  /:root\[data-theme='liquid'\]\s+\.liquid-sidebar-shell\.profile-material-shell/,
  "Liquid theme shell styling must target '.liquid-sidebar-shell.profile-material-shell' to preserve profile contract.",
);
ensureSourceContains(
  cssSource,
  /:root\[data-theme='liquid'\]\s+&\.profile-material-panel/,
  "Liquid settings/popover styling must target '&.profile-material-panel' inside @utility blocks to preserve profile contract.",
);

const clarityProtectedSurfaceFiles = [
  'app/src/components/TodayView.tsx',
  'app/src/components/ListView.tsx',
  'app/src/components/task-detail',
];
for (const relPath of clarityProtectedSurfaceFiles) {
  ensureFileContains(
    path.join(repoRoot, relPath),
    /\bclarity-first-surface\b/,
    `${relPath} must include 'clarity-first-surface' class to protect dense surfaces.`,
  );
}
// Inside @utility clarity-first-surface, `&.profile-material-panel` compiles to
// `.clarity-first-surface.profile-material-panel`. Match the source nesting syntax.
ensureSourceContains(
  cssSource,
  /&\.profile-material-panel/,
  "Clarity guardrail must cover same-node profile panel usage ('&.profile-material-panel' inside @utility clarity-first-surface).",
);
ensureSourceContains(
  cssSource,
  /&\.profile-material-shell/,
  "Clarity guardrail must cover same-node profile shell usage ('&.profile-material-shell' inside @utility clarity-first-surface).",
);

console.log(`[theme_tokens] OK: concrete themes from shared/src/types.ts (${concreteThemes.length}): ${concreteThemes.join(', ')}`);
console.log(`[theme_tokens] OK: required semantic CSS variables from :root (${requiredVariables.length})`);
console.log('[theme_tokens] OK: all concrete themes define complete semantic token coverage');
console.log(`[theme_tokens] OK: appearance profiles from shared/src/types.ts (${appearanceProfiles.length}): ${appearanceProfiles.join(', ')}`);
console.log("[theme_tokens] OK: bounded material and clarity-first surface hooks are present");
