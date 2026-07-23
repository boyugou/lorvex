#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import ts from 'typescript';

const SCRIPT_TAG = '[verify:appselect-variant-contract]';
const ALLOWED_VARIANTS = new Set(['default', 'muted', 'inline']);

function resolveRepoRoot() {
  const scriptPath = fileURLToPath(import.meta.url);
  return path.resolve(path.dirname(scriptPath), '..', '..');
}

function fail(message) {
  throw new Error(`${SCRIPT_TAG} ${message}`);
}

function collectTsxFiles(rootPath, skipDirs) {
  const files = [];

  function walk(currentPath) {
    const stats = fs.statSync(currentPath);
    if (stats.isDirectory()) {
      const entries = fs.readdirSync(currentPath).sort((a, b) => a.localeCompare(b));
      for (const entry of entries) {
        if (skipDirs.has(entry)) continue;
        walk(path.join(currentPath, entry));
      }
      return;
    }

    if (path.extname(currentPath).toLowerCase() === '.tsx') {
      files.push(currentPath);
    }
  }

  walk(rootPath);
  return files;
}

function walk(node, visitor) {
  visitor(node);
  ts.forEachChild(node, (child) => walk(child, visitor));
}

function jsxTagNameEqualsAppSelect(tagName) {
  return ts.isIdentifier(tagName) && tagName.text === 'AppSelect';
}

function lineNumberForNode(sourceFile, node) {
  return sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile)).line + 1;
}

function verifySingleFileAppSelectVariants(filePath, repoRoot) {
  const source = fs.readFileSync(filePath, 'utf8');
  const sourceFile = ts.createSourceFile(filePath, source, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);

  const relPath = path.relative(repoRoot, filePath);
  const violations = [];
  let totalTags = 0;

  const inspectTag = (tagNode, attributes) => {
    if (!jsxTagNameEqualsAppSelect(tagNode.tagName)) return;
    totalTags += 1;

    const variantAttr = attributes.properties.find((property) =>
      ts.isJsxAttribute(property) && property.name.text === 'variant');

    const line = lineNumberForNode(sourceFile, tagNode);

    if (!variantAttr) {
      violations.push(`${relPath}:${line} missing required variant prop on <AppSelect>`);
      return;
    }

    const initializer = variantAttr.initializer;
    if (!initializer || !ts.isStringLiteral(initializer)) {
      violations.push(
        `${relPath}:${line} AppSelect variant must be a string literal in {default|muted|inline}; received dynamic expression`,
      );
      return;
    }

    const variant = initializer.text;
    if (!ALLOWED_VARIANTS.has(variant)) {
      violations.push(
        `${relPath}:${line} invalid variant \"${variant}\"; allowed: ${Array.from(ALLOWED_VARIANTS).join(', ')}`,
      );
    }
  };

  walk(sourceFile, (node) => {
    if (ts.isJsxSelfClosingElement(node)) {
      inspectTag(node, node.attributes);
    } else if (ts.isJsxOpeningElement(node)) {
      inspectTag(node, node.attributes);
    }
  });

  return { violations, totalTags };
}

export function verifyAppSelectVariantContract({ srcRoot = path.join(resolveRepoRoot(), 'app', 'src') } = {}) {
  if (!fs.existsSync(srcRoot)) {
    fail(`missing source directory: ${path.relative(resolveRepoRoot(), srcRoot)}`);
  }

  const repoRoot = resolveRepoRoot();
  const files = collectTsxFiles(srcRoot, new Set(['node_modules', 'dist', 'target', '.git']));

  const violations = [];
  let totalTags = 0;

  for (const filePath of files) {
    const result = verifySingleFileAppSelectVariants(filePath, repoRoot);
    violations.push(...result.violations);
    totalTags += result.totalTags;
  }

  if (violations.length > 0) {
    throw new Error(violations.join('\n'));
  }

  return { ok: true, totalTags };
}

function runCli() {
  try {
    const { totalTags } = verifyAppSelectVariantContract();
    console.log(`${SCRIPT_TAG} OK: ${totalTags} AppSelect callsites declare explicit valid variants.`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    for (const line of message.split('\n')) {
      if (!line.trim()) continue;
      console.error(line.startsWith(SCRIPT_TAG) ? line : `${SCRIPT_TAG} ${line}`);
    }
    process.exit(1);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runCli();
}
