#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import ts from 'typescript';
import { fileURLToPath } from 'node:url';
import { readSourceTree } from '../lib/verifier_runtime.mjs';

const SCRIPT_TAG = '[verify:mobile-sync-cadence-contract]';

function resolveRepoRoot() {
  const scriptPath = fileURLToPath(import.meta.url);
  return path.resolve(path.dirname(scriptPath), '..', '..');
}

function fail(message) {
  throw new Error(`${SCRIPT_TAG} ${message}`);
}

function assert(condition, message) {
  if (!condition) {
    fail(message);
  }
}

function parseTypeScriptFile(filePath, scriptKind) {
  assert(fs.existsSync(filePath), `missing required file: ${filePath}`);
  const source = fs.readFileSync(filePath, 'utf8');
  return ts.createSourceFile(filePath, source, ts.ScriptTarget.Latest, true, scriptKind);
}

function parseTypeScriptTree(rootPath, scriptKind) {
  const source = readSourceTree(rootPath);
  assert(source.trim().length > 0, `missing required file: ${rootPath}`);
  return ts.createSourceFile(rootPath, source, ts.ScriptTarget.Latest, true, scriptKind);
}

function parseSyncSourceFile(repoRoot, scriptKind) {
  const legacySyncFilePath = path.join(repoRoot, 'app', 'src', 'lib', 'sync.ts');
  const syncDirPath = path.join(repoRoot, 'app', 'src', 'lib', 'sync');
  assert(!fs.existsSync(legacySyncFilePath), 'legacy app/src/lib/sync.ts must not be reintroduced');
  assert(fs.existsSync(syncDirPath), `missing required directory: ${syncDirPath}`);
  const source = readSourceTree(syncDirPath);
  assert(source.trim().length > 0, `missing required source under: ${syncDirPath}`);
  return ts.createSourceFile(syncDirPath, source, ts.ScriptTarget.Latest, true, scriptKind);
}

function walk(node, visitor) {
  visitor(node);
  ts.forEachChild(node, (child) => walk(child, visitor));
}

function hasImportFromModule(sourceFile, modulePath) {
  return sourceFile.statements.some((statement) =>
    ts.isImportDeclaration(statement)
    && ts.isStringLiteral(statement.moduleSpecifier)
    && statement.moduleSpecifier.text === modulePath);
}

function importedNamesFromModule(sourceFile, modulePath) {
  const names = new Set();
  for (const statement of sourceFile.statements) {
    if (!ts.isImportDeclaration(statement)) continue;
    if (!ts.isStringLiteral(statement.moduleSpecifier) || statement.moduleSpecifier.text !== modulePath) continue;
    if (!statement.importClause?.namedBindings || !ts.isNamedImports(statement.importClause.namedBindings)) continue;
    for (const element of statement.importClause.namedBindings.elements) {
      names.add(element.name.text);
    }
  }
  return names;
}

function hasConstDeclaration(sourceFile, constantName) {
  return sourceFile.statements.some((statement) => {
    if (!ts.isVariableStatement(statement)) return false;
    if (!(statement.declarationList.flags & ts.NodeFlags.Const)) return false;
    return statement.declarationList.declarations.some((declaration) =>
      ts.isIdentifier(declaration.name) && declaration.name.text === constantName);
  });
}

function hasFunctionDeclaration(sourceFile, functionName) {
  return sourceFile.statements.some((statement) =>
    ts.isFunctionDeclaration(statement)
    && statement.name?.text === functionName);
}

function hasIdentifierUsage(sourceFile, identifierName) {
  let found = false;
  walk(sourceFile, (node) => {
    if (found) return;
    if (ts.isIdentifier(node) && node.text === identifierName) {
      found = true;
    }
  });
  return found;
}

function propertyChainText(node) {
  if (ts.isIdentifier(node)) return node.text;
  if (ts.isPropertyAccessExpression(node) || ts.isPropertyAccessChain(node)) {
    const left = propertyChainText(node.expression);
    return left ? `${left}.${node.name.text}` : node.name.text;
  }
  if (ts.isParenthesizedExpression(node) || ts.isNonNullExpression(node)) {
    return propertyChainText(node.expression);
  }
  return null;
}

function hasPropertyChain(sourceFile, expectedChain) {
  let found = false;
  walk(sourceFile, (node) => {
    if (found) return;
    if (!(ts.isPropertyAccessExpression(node) || ts.isPropertyAccessChain(node))) return;
    const chain = propertyChainText(node);
    if (chain === expectedChain) {
      found = true;
    }
  });
  return found;
}

function hasMobilePlatformBranch(sourceFile, platformLiteral) {
  let found = false;
  walk(sourceFile, (node) => {
    if (found) return;
    if (!ts.isBinaryExpression(node)) return;
    if (
      node.operatorToken.kind !== ts.SyntaxKind.EqualsEqualsEqualsToken
      && node.operatorToken.kind !== ts.SyntaxKind.EqualsEqualsToken
    ) {
      return;
    }

    const leftLiteral = ts.isStringLiteral(node.left) ? node.left.text : null;
    const rightLiteral = ts.isStringLiteral(node.right) ? node.right.text : null;

    const leftIsMobilePlatform =
      (ts.isIdentifier(node.left) && node.left.text === 'mobilePlatform')
      || (ts.isPropertyAccessExpression(node.left) && node.left.name.text === 'mobilePlatform')
      || (ts.isPropertyAccessChain(node.left) && node.left.name.text === 'mobilePlatform');

    const rightIsMobilePlatform =
      (ts.isIdentifier(node.right) && node.right.text === 'mobilePlatform')
      || (ts.isPropertyAccessExpression(node.right) && node.right.name.text === 'mobilePlatform')
      || (ts.isPropertyAccessChain(node.right) && node.right.name.text === 'mobilePlatform');

    if ((leftIsMobilePlatform && rightLiteral === platformLiteral) || (rightIsMobilePlatform && leftLiteral === platformLiteral)) {
      found = true;
    }
  });
  return found;
}

function hasExponentialBackoff(sourceFile) {
  let found = false;
  walk(sourceFile, (node) => {
    if (found) return;
    if (ts.isCallExpression(node) && ts.isPropertyAccessExpression(node.expression)) {
      if (
        ts.isIdentifier(node.expression.expression)
        && node.expression.expression.text === 'Math'
        && node.expression.name.text === 'pow'
      ) {
        found = true;
      }
    }
    if (ts.isBinaryExpression(node) && node.operatorToken.kind === ts.SyntaxKind.AsteriskAsteriskToken) {
      found = true;
    }
  });
  return found;
}

function hasWindowEventListener(sourceFile, eventName) {
  // Decomposition aside, window listeners now go through the
  // `browserHost.addWindowListener(...)` shim so the cadence engine
  // is testable without a live `window`. Accept any of:
  //   - `window.addEventListener('event', ...)` (legacy direct path)
  //   - `<host>.addWindowListener('event', ...)` (modern host shim)
  // The structural intent (the cadence engine subscribes to the named
  // window event) is preserved by either form.
  let found = false;
  walk(sourceFile, (node) => {
    if (found) return;
    if (!ts.isCallExpression(node)) return;
    if (!(ts.isPropertyAccessExpression(node.expression) || ts.isPropertyAccessChain(node.expression))) return;
    const methodName = node.expression.name.text;
    const isLegacyWindowAddEventListener =
      methodName === 'addEventListener'
      && ts.isIdentifier(node.expression.expression)
      && node.expression.expression.text === 'window';
    const isHostAddWindowListener = methodName === 'addWindowListener';
    if (!isLegacyWindowAddEventListener && !isHostAddWindowListener) return;
    const [firstArg] = node.arguments;
    if (firstArg && ts.isStringLiteral(firstArg) && firstArg.text === eventName) {
      found = true;
    }
  });
  return found;
}

export function verifyMobileSyncCadenceContract({ repoRoot = resolveRepoRoot() } = {}) {
  // The legacy single-file `sync.ts` was decomposed into a `sync/`
  // directory (cadence.ts, network.ts, runtime.ts, ...). Keep this
  // contract pinned to the directory shape so a stale facade cannot
  // satisfy mobile cadence checks by accident.
  const legacySyncFilePath = path.join(repoRoot, 'app', 'src', 'lib', 'sync.ts');
  const syncDirPath = path.join(repoRoot, 'app', 'src', 'lib', 'sync');
  assert(!fs.existsSync(legacySyncFilePath), 'legacy app/src/lib/sync.ts must not exist');
  assert(fs.existsSync(syncDirPath), 'missing app/src/lib/sync/ directory');
  const syncSourceFile = parseSyncSourceFile(repoRoot, ts.ScriptKind.TS);

  const platformImports = importedNamesFromModule(syncSourceFile, './platform');
  const nestedPlatformImports = importedNamesFromModule(syncSourceFile, '../platform');
  const subfolderPlatformImports = importedNamesFromModule(syncSourceFile, '../platform/platform');
  assert(
    (
      hasImportFromModule(syncSourceFile, './platform')
        || hasImportFromModule(syncSourceFile, '../platform')
        || hasImportFromModule(syncSourceFile, '../platform/platform')
    )
      && (
        platformImports.has('getRuntimeProfile')
        || nestedPlatformImports.has('getRuntimeProfile')
        || subfolderPlatformImports.has('getRuntimeProfile')
        || (platformImports.has('isLikelyMobileRuntime') && platformImports.has('getMobilePlatform'))
        || (nestedPlatformImports.has('isLikelyMobileRuntime') && nestedPlatformImports.has('getMobilePlatform'))
        || (subfolderPlatformImports.has('isLikelyMobileRuntime') && subfolderPlatformImports.has('getMobilePlatform'))
      ),
    'sync.ts must use canonical platform runtime helpers for mobile cadence control',
  );

  const requiredConstants = [
    'SYNC_LOOP_DESKTOP_MS',
    'SYNC_LOOP_ANDROID_ACTIVE_MS',
    'SYNC_LOOP_ANDROID_BACKGROUND_MS',
    'SYNC_LOOP_MOBILE_LOW_BANDWIDTH_MS',
    'SYNC_LOOP_OFFLINE_MS',
    'SYNC_LOOP_ERROR_BACKOFF_BASE_MS',
    'SYNC_LOOP_ERROR_BACKOFF_MAX_MS',
  ];

  for (const constantName of requiredConstants) {
    assert(
      hasConstDeclaration(syncSourceFile, constantName),
      `sync.ts must define cadence constant: ${constantName}`,
    );
  }

  assert(
    hasFunctionDeclaration(syncSourceFile, 'computeSyncCadenceDelay'),
    'sync.ts must implement computeSyncCadenceDelay()',
  );

  assert(
    hasMobilePlatformBranch(syncSourceFile, 'android') && !hasMobilePlatformBranch(syncSourceFile, 'ios'),
    'sync.ts must apply Android cadence only; iOS/iPadOS cadence belongs to apps/apple',
  );

  // Decomposition aside, the canonical online-state reader was
  // refactored from a direct `navigator.onLine` access into a host
  // shim (`navigatorState.onLine`) so background-sync logic can be
  // unit-tested without a live `navigator`. Accept either chain — the
  // structural intent ("the cadence engine reads online state via the
  // `.onLine` Navigator property") is preserved by both.
  assert(
    hasPropertyChain(syncSourceFile, 'navigator.onLine')
      || hasPropertyChain(syncSourceFile, 'navigatorState.onLine'),
    'sync module must account for online/offline state via navigator.onLine (directly or via host shim)',
  );

  assert(
    hasIdentifierUsage(syncSourceFile, 'effectiveType') && hasIdentifierUsage(syncSourceFile, 'saveData'),
    'sync.ts must read network quality hints (effectiveType/saveData)',
  );

  assert(
    hasIdentifierUsage(syncSourceFile, 'consecutiveErrorCount') && hasExponentialBackoff(syncSourceFile),
    'sync.ts must apply exponential backoff by consecutive error count',
  );

  assert(
    hasWindowEventListener(syncSourceFile, 'online') && hasWindowEventListener(syncSourceFile, 'offline'),
    'sync.ts must listen to online/offline events for cadence updates',
  );

  return { ok: true };
}

function runCli() {
  try {
    verifyMobileSyncCadenceContract();
    console.log(`${SCRIPT_TAG} Mobile sync cadence contract checks passed.`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.startsWith(SCRIPT_TAG) ? message : `${SCRIPT_TAG} ${message}`);
    process.exit(1);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runCli();
}
