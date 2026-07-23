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

const SCRIPT_TAG = '[verify:markdown-prose-logical-css]';

const PROSE_SELECTOR_PATTERNS = [
  '.markdown-content',
  '.milkdown-editor-wrapper .ProseMirror',
];

const PHYSICAL_PROPERTIES = new Set([
  'border-left',
  'border-right',
  'left',
  'margin-left',
  'margin-right',
  'padding-left',
  'padding-right',
  'right',
]);

function lineNumberForOffset(source, offset) {
  return source.slice(0, offset).split(/\r?\n/).length;
}

function splitCssValue(value) {
  const tokens = [];
  let current = '';
  let parenDepth = 0;

  for (const char of value.trim()) {
    if (char === '(') parenDepth += 1;
    if (char === ')') parenDepth = Math.max(0, parenDepth - 1);

    if (/\s/.test(char) && parenDepth === 0) {
      if (current) {
        tokens.push(current);
        current = '';
      }
      continue;
    }

    current += char;
  }

  if (current) tokens.push(current);
  return tokens;
}

function hasPhysicalBorderRadius(value) {
  const tokens = splitCssValue(value);
  if (tokens.length < 4) return false;
  const [first, second, third, fourth] = tokens;
  return first !== third || second !== fourth;
}

function isProseSelector(selector) {
  return PROSE_SELECTOR_PATTERNS.some((pattern) => selector.includes(pattern));
}

function normalizeSelector(rawSelector) {
  return rawSelector
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .trim();
}

export function findMarkdownProseLogicalCssViolations(source) {
  const findings = [];
  const rulePattern = /([^{}]+)\{([^{}]*)\}/g;
  let match;

  while ((match = rulePattern.exec(source)) !== null) {
    const [, rawSelector, rawBlock] = match;
    const selector = normalizeSelector(rawSelector);
    if (!isProseSelector(selector)) continue;

    let declarationOffset = 0;
    for (const declaration of rawBlock.split(';')) {
      const declarationStart = match.index + rawSelector.length + 1 + declarationOffset;
      declarationOffset += declaration.length + 1;

      const declarationMatch = declaration.match(/^\s*([a-z-]+)\s*:\s*(.*?)\s*$/s);
      if (!declarationMatch) continue;

      const [, property, value] = declarationMatch;
      if (PHYSICAL_PROPERTIES.has(property)) {
        findings.push({
          line: lineNumberForOffset(source, declarationStart),
          selector,
          property,
          value,
          reason: 'use logical inline/start/end property names for markdown prose',
        });
        continue;
      }

      if (property === 'border-radius' && hasPhysicalBorderRadius(value)) {
        findings.push({
          line: lineNumberForOffset(source, declarationStart),
          selector,
          property,
          value,
          reason: 'use logical corner radii for asymmetric markdown prose corners',
        });
      }
    }
  }

  return findings;
}

export function verifyMarkdownProseLogicalCss({
  repoRoot = resolveRepoRootFromMeta(import.meta.url),
} = {}) {
  const cssPath = path.join(repoRoot, 'app/src/index.css');
  assertContract(fs.existsSync(cssPath), SCRIPT_TAG, `missing required file: ${cssPath}`);
  const source = resolveCssImportGraph(cssPath);
  const findings = findMarkdownProseLogicalCssViolations(source);

  assertContract(
    findings.length === 0,
    SCRIPT_TAG,
    `markdown prose CSS must use logical inline/start/end properties:\n${findings
      .map((finding) => `  ${path.relative(repoRoot, cssPath)}:${finding.line} ${finding.selector} ${finding.property}: ${finding.value} (${finding.reason})`)
      .join('\n')}`,
  );

  return {
    ok: true,
    selectors: PROSE_SELECTOR_PATTERNS,
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runVerifierCli({
    scriptTag: SCRIPT_TAG,
    successMessage: 'Markdown prose logical CSS checks passed.',
    run: () => verifyMarkdownProseLogicalCss(),
  });
}
