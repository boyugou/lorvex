#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import postcss from 'postcss';
import { fileURLToPath } from 'node:url';

import { resolveCssImportGraph } from '../lib/css_graph.mjs';

const SCRIPT_TAG = '[verify:android-typography-contract]';
const ANDROID_SELECTOR_NORMALIZED = ":root[data-mobile-os='android']";

function resolveRepoRoot() {
  const scriptPath = fileURLToPath(import.meta.url);
  return path.resolve(path.dirname(scriptPath), '..', '..');
}

function fail(message) {
  throw new Error(`${SCRIPT_TAG} ${message}`);
}

function normalizeSelector(selector) {
  return selector.replace(/\s+/g, '').replace(/"/g, "'").trim();
}

function normalizeFontToken(token) {
  return token.trim().replace(/^['"]|['"]$/g, '').toLowerCase();
}

function parseFontFamilyTokens(value) {
  return value
    .split(',')
    .map((token) => normalizeFontToken(token))
    .filter(Boolean);
}

export function verifyAndroidTypographyContract({ cssPath = path.join(resolveRepoRoot(), 'app', 'src', 'index.css') } = {}) {
  if (!fs.existsSync(cssPath)) {
    fail('missing app/src/index.css');
  }

  const css = resolveCssImportGraph(cssPath);

  let root;
  try {
    root = postcss.parse(css, { from: cssPath });
  } catch {
    fail('unable to parse app/src/index.css');
  }

  let selectorFound = false;
  const fontValues = [];

  root.walkRules((rule) => {
    const selectors = rule.selectors ?? rule.selector.split(',').map((selector) => selector.trim());
    const hasAndroidSelector = selectors.some(
      (selector) => normalizeSelector(selector) === ANDROID_SELECTOR_NORMALIZED,
    );

    if (!hasAndroidSelector) return;
    selectorFound = true;

    rule.walkDecls('--app-font-family', (decl) => {
      fontValues.push(decl.value);
    });
  });

  if (!selectorFound) {
    fail("missing Android typography selector :root[data-mobile-os='android']");
  }

  if (fontValues.length === 0) {
    fail('Android typography block must define --app-font-family');
  }

  const fontTokens = parseFontFamilyTokens(fontValues.join(','));
  if (!fontTokens.includes('roboto')) {
    fail('Android typography stack must include Roboto');
  }
  if (!fontTokens.includes('noto sans cjk sc')) {
    fail('Android typography stack must include Noto Sans CJK SC');
  }

  return { ok: true };
}

function runCli() {
  try {
    verifyAndroidTypographyContract();
    console.log(`${SCRIPT_TAG} Android typography contract checks passed.`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.startsWith(SCRIPT_TAG) ? message : `${SCRIPT_TAG} ${message}`);
    process.exit(1);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runCli();
}
