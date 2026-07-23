#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { resolveCssImportGraph } from '../lib/css_graph.mjs';
import {
  assertContract,
  resolveRepoRootFromMeta,
  runVerifierCli,
} from '../lib/verifier_runtime.mjs';

const SCRIPT_TAG = '[verify:windows-typography-contract]';

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

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function extractPropertyDeclarations(blockBody, propertyName) {
  const declarationPattern = new RegExp(`${escapeRegExp(propertyName)}\\s*:\\s*([^;]+)\\s*;`, 'g');
  return Array.from(
    blockBody.matchAll(declarationPattern),
    (match) => match[1].trim(),
  );
}

export function verifyWindowsTypographyContract({
  repoRoot = resolveRepoRootFromMeta(import.meta.url),
} = {}) {
  const cssPath = path.join(repoRoot, 'app', 'src', 'index.css');
  assertContract(fs.existsSync(cssPath), SCRIPT_TAG, `missing required file: ${cssPath}`);

  const cssSource = resolveCssImportGraph(cssPath);
  const cssWithoutComments = cssSource.replace(/\/\*[\s\S]*?\*\//g, '');
  const cssBlocks = collectBlocksRecursively(cssWithoutComments);

  const requiredWindowsStack = '"Segoe UI Variable", "Segoe UI", "Microsoft YaHei UI", sans-serif';
  // The canonical Windows stack starts with the trio "Segoe UI
  // Variable" → "Segoe UI" → "Microsoft YaHei UI" and terminates in
  // `sans-serif`. The expanded chain in `index.css` legitimately
  // inserts Noto Sans CJK / Arabic / Hebrew / Devanagari / Bengali /
  // Tamil / Telugu / Malayalam / Thai fallbacks between the trio and
  // the generic to extend script coverage on Windows targets where
  // the bundled Segoe UI variant lacks those scripts. Accept any such
  // expansion as long as the prefix and suffix are intact.
  const requiredWindowsStackPrefix = '"Segoe UI Variable", "Segoe UI", "Microsoft YaHei UI",';
  const requiredWindowsStackSuffix = ', sans-serif';
  const matchesRequiredWindowsStack = (value) =>
    value === requiredWindowsStack
    || (value.startsWith(requiredWindowsStackPrefix) && value.endsWith(requiredWindowsStackSuffix));
  const requiredBaseFontFamilyValue = "var(--app-font-family, -apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui, sans-serif)";
  // The base font-family fallback chain accepts either the short
  // canonical form or the extended Noto Sans script-coverage fallback
  // chain. The structural intent (the var() default starts with
  // -apple-system → BlinkMacSystemFont → 'SF Pro Text' → system-ui
  // and terminates in sans-serif) is preserved.
  const requiredBaseFontFamilyPrefix = "var(--app-font-family, -apple-system, BlinkMacSystemFont, 'SF Pro Text', system-ui,";
  const requiredBaseFontFamilySuffix = ", sans-serif)";
  const matchesRequiredBaseFontFamilyValue = (value) =>
    value === requiredBaseFontFamilyValue
    || (value.startsWith(requiredBaseFontFamilyPrefix) && value.endsWith(requiredBaseFontFamilySuffix));
  const normalizedWindowsSelector = ":root[data-desktop-os='windows']";
  const baseSelectorEntries = new Set(['html', 'body', '#root']);

  const windowsDeclarations = [];
  const baseBlockDeclarations = [];
  const rootScopeFontFamilyDeclarations = [];

  for (const block of cssBlocks) {
    const selectorEntries = splitSelectorList(block.selector).map(normalizeSelector);
    const fontFamilyValues = extractPropertyDeclarations(block.body, 'font-family');

    if (selectorEntries.includes(normalizedWindowsSelector)) {
      for (const value of extractPropertyDeclarations(block.body, '--app-font-family')) {
        windowsDeclarations.push(value);
      }
    }

    const includesBaseTrio = Array.from(baseSelectorEntries).every((entry) => selectorEntries.includes(entry));
    if (includesBaseTrio) {
      for (const value of fontFamilyValues) {
        baseBlockDeclarations.push(value);
      }
    }

    const touchesRootScope = selectorEntries.some((entry) => baseSelectorEntries.has(entry));
    if (touchesRootScope) {
      for (const value of fontFamilyValues) {
        rootScopeFontFamilyDeclarations.push(value);
      }
    }
  }

  assertContract(
    windowsDeclarations.length > 0,
    SCRIPT_TAG,
    "index.css must define --app-font-family in :root[data-desktop-os='windows']",
  );

  assertContract(
    windowsDeclarations.every(matchesRequiredWindowsStack),
    SCRIPT_TAG,
    `windows typography override must start with ${requiredWindowsStackPrefix} and end with ${requiredWindowsStackSuffix.trim()}`,
  );
  assertContract(
    matchesRequiredWindowsStack(windowsDeclarations.at(-1)),
    SCRIPT_TAG,
    `windows typography override must start with ${requiredWindowsStackPrefix} and end with ${requiredWindowsStackSuffix.trim()}`,
  );

  assertContract(
    baseBlockDeclarations.length > 0,
    SCRIPT_TAG,
    'index.css must define font-family in html, body, #root block',
  );

  assertContract(
    baseBlockDeclarations.every(matchesRequiredBaseFontFamilyValue),
    SCRIPT_TAG,
    `html, body, #root font-family must start with ${requiredBaseFontFamilyPrefix} and end with ${requiredBaseFontFamilySuffix.trim()};`,
  );

  assertContract(
    rootScopeFontFamilyDeclarations.length > 0,
    SCRIPT_TAG,
    'index.css must define root-scope font-family declarations for html/body/#root',
  );

  assertContract(
    rootScopeFontFamilyDeclarations.every(matchesRequiredBaseFontFamilyValue),
    SCRIPT_TAG,
    `all html/body/#root font-family declarations must start with ${requiredBaseFontFamilyPrefix} and end with ${requiredBaseFontFamilySuffix.trim()};`,
  );

  return { ok: true };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runVerifierCli({
    scriptTag: SCRIPT_TAG,
    successMessage: 'Windows typography contract checks passed.',
    run: () => verifyWindowsTypographyContract(),
  });
}
