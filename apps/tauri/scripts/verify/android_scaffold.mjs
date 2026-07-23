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

const SCRIPT_TAG = '[verify:android-scaffold]';

function readRequiredText(repoRoot, relPath) {
  const absolutePath = path.join(repoRoot, relPath);
  assertContract(fs.existsSync(absolutePath), SCRIPT_TAG, `missing file: ${relPath}`);
  return fs.readFileSync(absolutePath, 'utf8');
}

function parseTypeScriptSource(filePath, source, scriptKind) {
  return ts.createSourceFile(filePath, source, ts.ScriptTarget.Latest, true, scriptKind);
}

function walk(node, visitor) {
  visitor(node);
  ts.forEachChild(node, (child) => walk(child, visitor));
}

function hasExportModifier(node) {
  return Boolean(node.modifiers?.some((modifier) => modifier.kind === ts.SyntaxKind.ExportKeyword));
}

function findExportedTypeAlias(sourceFile, aliasName) {
  return sourceFile.statements.find((statement) =>
    ts.isTypeAliasDeclaration(statement)
    && hasExportModifier(statement)
    && statement.name.text === aliasName);
}

function findExportedFunction(sourceFile, functionName) {
  return sourceFile.statements.find((statement) =>
    ts.isFunctionDeclaration(statement)
    && hasExportModifier(statement)
    && statement.name?.text === functionName);
}

function assertMobilePlatformType(sourceFile) {
  const alias = findExportedTypeAlias(sourceFile, 'MobilePlatform');
  // The `MobilePlatform` type alias is declared in `platform.logic.ts`
  // post-decomposition; `platform.ts` re-exports it. The contract is
  // anchored at the source-of-truth declaration site.
  assertContract(Boolean(alias), SCRIPT_TAG, "platform.logic.ts must export type alias 'MobilePlatform'");

  const typeNode = alias.type;
  assertContract(ts.isUnionTypeNode(typeNode), SCRIPT_TAG, 'MobilePlatform must be a string-literal union');
  const literals = typeNode.types
    .filter((member) =>
      ts.isLiteralTypeNode(member)
      && (ts.isStringLiteral(member.literal) || ts.isNoSubstitutionTemplateLiteral(member.literal)))
    .map((member) => member.literal.text);
  for (const expected of ['android', 'unknown']) {
    assertContract(
      literals.includes(expected),
      SCRIPT_TAG,
      `MobilePlatform must include '${expected}' literal`,
    );
  }
  assertContract(
    !literals.includes('ios'),
    SCRIPT_TAG,
    "MobilePlatform must not include 'ios'; Apple mobile runtimes belong to apps/apple",
  );
}

function assertExportedFunctions(sourceFile) {
  for (const functionName of ['getMobilePlatform']) {
    assertContract(
      Boolean(findExportedFunction(sourceFile, functionName)),
      SCRIPT_TAG,
      `platform.ts must export function '${functionName}'`,
    );
  }
}

function hasDocumentElementSetAttribute(sourceFile, attributeName) {
  // Current scaffold keeps DOM writes in main.runtime.ts through the
  // injected document target (`deps.documentTarget.documentElement...`).
  let found = false;
  walk(sourceFile, (node) => {
    if (found || !ts.isCallExpression(node)) return;
    if (!ts.isPropertyAccessExpression(node.expression)) return;
    if (node.expression.name.text !== 'setAttribute') return;
    if (!ts.isPropertyAccessExpression(node.expression.expression)) return;
    const root = node.expression.expression;
    if (root.name.text !== 'documentElement') return;
    if (!ts.isPropertyAccessExpression(root.expression)) return;
    if (root.expression.name.text !== 'documentTarget') return;

    const [firstArg] = node.arguments;
    if (!firstArg) return;
    if (
      (ts.isStringLiteral(firstArg) || ts.isNoSubstitutionTemplateLiteral(firstArg))
      && firstArg.text === attributeName
    ) {
      found = true;
    }
  });
  return found;
}

export function verifyAndroidScaffoldContract({
  repoRoot = resolveRepoRootFromMeta(import.meta.url),
} = {}) {
  const androidConfigText = readRequiredText(repoRoot, 'app/src-tauri/tauri.android.conf.json');
  let androidConfig;
  try {
    androidConfig = JSON.parse(androidConfigText);
  } catch (error) {
    assertContract(false, SCRIPT_TAG, `tauri.android.conf.json is invalid JSON: ${String(error)}`);
  }

  const windows = androidConfig?.app?.windows;
  assertContract(Array.isArray(windows), SCRIPT_TAG, 'tauri.android.conf.json must define app.windows as an array');
  const labels = windows
    .map((windowDef) => windowDef?.label)
    .filter((label) => typeof label === 'string');
  assertContract(
    labels.length === 1 && labels[0] === 'main',
    SCRIPT_TAG,
    `Android config should expose only the main window; got labels: ${labels.join(', ') || '(none)'}`,
  );
  assertContract(
    !labels.includes('focus') && !labels.includes('popover'),
    SCRIPT_TAG,
    'Android config must not include desktop-only focus/popover windows',
  );

  const platformPath = path.join(repoRoot, 'app/src/lib/platform/platform.ts');
  const platformSource = readRequiredText(repoRoot, 'app/src/lib/platform/platform.ts');
  const platformSourceFile = parseTypeScriptSource(platformPath, platformSource, ts.ScriptKind.TS);
  const platformLogicPath = path.join(repoRoot, 'app/src/lib/platform/platform.logic.ts');
  const platformLogicSource = readRequiredText(repoRoot, 'app/src/lib/platform/platform.logic.ts');
  const platformLogicSourceFile = parseTypeScriptSource(
    platformLogicPath,
    platformLogicSource,
    ts.ScriptKind.TS,
  );
  assertMobilePlatformType(platformLogicSourceFile);
  assertExportedFunctions(platformSourceFile);

  const mainPath = path.join(repoRoot, 'app/src/main.tsx');
  const mainSource = readRequiredText(repoRoot, 'app/src/main.tsx');
  parseTypeScriptSource(mainPath, mainSource, ts.ScriptKind.TSX);
  assertContract(
    /installMainDocumentRuntime\(\s*\{[\s\S]*mobilePlatform:\s*getMobilePlatform\(\)/.test(mainSource),
    SCRIPT_TAG,
    'main.tsx must install main document runtime with getMobilePlatform()',
  );
  const mainRuntimePath = path.join(repoRoot, 'app/src/main.runtime.ts');
  const mainRuntimeSource = readRequiredText(repoRoot, 'app/src/main.runtime.ts');
  const mainRuntimeSourceFile = parseTypeScriptSource(
    mainRuntimePath,
    mainRuntimeSource,
    ts.ScriptKind.TS,
  );
  assertContract(
    hasDocumentElementSetAttribute(mainRuntimeSourceFile, 'data-mobile-os'),
    SCRIPT_TAG,
    'main.runtime.ts must set documentElement data-mobile-os attribute',
  );

  return { ok: true };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runVerifierCli({
    scriptTag: SCRIPT_TAG,
    successMessage: 'Android scaffold verification passed.',
    run: () => verifyAndroidScaffoldContract(),
  });
}
