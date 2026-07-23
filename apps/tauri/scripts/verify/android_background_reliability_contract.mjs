#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import ts from 'typescript';
import { fileURLToPath } from 'node:url';
import {
  assertContract,
  readSourceTree,
  resolveRepoRootFromMeta,
  runVerifierCli,
} from '../lib/verifier_runtime.mjs';

const SCRIPT_TAG = '[verify:android-background-reliability-contract]';

function walk(node, visitor) {
  visitor(node);
  ts.forEachChild(node, (child) => walk(child, visitor));
}

function parseTypeScriptFile(filePath) {
  assertContract(fs.existsSync(filePath), SCRIPT_TAG, `missing required file: ${filePath}`);
  const source = fs.readFileSync(filePath, 'utf8');
  return ts.createSourceFile(filePath, source, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
}

function parseTypeScriptTree(rootPath) {
  const source = readSourceTree(rootPath);
  assertContract(source.trim().length > 0, SCRIPT_TAG, `missing required file: ${rootPath}`);
  return ts.createSourceFile(rootPath, source, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
}

function parseSyncSourceFile(repoRoot) {
  const legacySyncFilePath = path.join(repoRoot, 'app', 'src', 'lib', 'sync.ts');
  const syncDirPath = path.join(repoRoot, 'app', 'src', 'lib', 'sync');
  assertContract(
    !fs.existsSync(legacySyncFilePath),
    SCRIPT_TAG,
    'legacy app/src/lib/sync.ts must not be reintroduced',
  );
  assertContract(fs.existsSync(syncDirPath), SCRIPT_TAG, `missing required directory: ${syncDirPath}`);
  const source = readSourceTree(syncDirPath);
  assertContract(source.trim().length > 0, SCRIPT_TAG, `missing required source under: ${syncDirPath}`);
  return ts.createSourceFile(syncDirPath, source, ts.ScriptTarget.Latest, true, ts.ScriptKind.TS);
}

function hasConstAlias(sourceFile, constantName, targetIdentifierName) {
  return sourceFile.statements.some((statement) => {
    if (!ts.isVariableStatement(statement)) return false;
    if (!(statement.declarationList.flags & ts.NodeFlags.Const)) return false;
    return statement.declarationList.declarations.some((declaration) =>
      ts.isIdentifier(declaration.name)
      && declaration.name.text === constantName
      && declaration.initializer
      && ts.isIdentifier(declaration.initializer)
      && declaration.initializer.text === targetIdentifierName);
  });
}

function findHandlerBodyNodes(sourceFile, handlerName) {
  // Accepts: top-level function declarations, var-bound arrow/function
  // expressions, AND object-literal methods (modern controller shape:
  // `return { handlePageShow(running) { ... } }`). Returns *all*
  // matches because a name like `onPageShow` may bind a thin window
  // delegator while the actual predicate-bearing implementation lives
  // on the controller's `handlePageShow` method.
  const bodies = [];
  walk(sourceFile, (node) => {
    if (ts.isFunctionDeclaration(node) && node.name?.text === handlerName && node.body) {
      bodies.push(node.body);
      return;
    }

    if (
      ts.isMethodDeclaration(node)
      && ts.isIdentifier(node.name)
      && node.name.text === handlerName
      && node.body
    ) {
      bodies.push(node.body);
      return;
    }

    if (
      ts.isPropertyAssignment(node)
      && ts.isIdentifier(node.name)
      && node.name.text === handlerName
      && (ts.isArrowFunction(node.initializer) || ts.isFunctionExpression(node.initializer))
    ) {
      bodies.push(node.initializer.body);
      return;
    }

    if (!ts.isVariableDeclaration(node)) return;
    if (!ts.isIdentifier(node.name) || node.name.text !== handlerName) return;
    if (!node.initializer) return;
    if (
      ts.isArrowFunction(node.initializer)
      || ts.isFunctionExpression(node.initializer)
    ) {
      bodies.push(node.initializer.body);
    }
  });
  return bodies;
}

function findHandlerBodyNode(sourceFile, handlerName) {
  return findHandlerBodyNodes(sourceFile, handlerName)[0] ?? null;
}

function hasIdentifierCall(node, identifierName) {
  let found = false;
  walk(node, (current) => {
    if (found || !ts.isCallExpression(current)) return;
    if (!ts.isIdentifier(current.expression) || current.expression.text !== identifierName) return;
    found = true;
  });
  return found;
}

function hasScheduleImmediateTickTrueCall(node) {
  let found = false;
  walk(node, (current) => {
    if (found || !ts.isCallExpression(current)) return;
    if (!ts.isIdentifier(current.expression) || current.expression.text !== 'scheduleImmediateTick') return;
    const [firstArg] = current.arguments;
    if (firstArg && firstArg.kind === ts.SyntaxKind.TrueKeyword) {
      found = true;
    }
  });
  return found;
}

function hasWindowEventListener(sourceFile, eventName, handlerName) {
  // Post-decomposition the cadence engine subscribes to window events
  // through a `browserHost.addWindowListener(...)` shim instead of
  // calling `window.addEventListener(...)` directly so the runtime can
  // be unit-tested without a live `window`. Accept either form.
  let found = false;
  walk(sourceFile, (node) => {
    if (found || !ts.isCallExpression(node)) return;
    if (!ts.isPropertyAccessExpression(node.expression)) return;
    const methodName = node.expression.name.text;
    const isLegacyWindowAddEventListener =
      methodName === 'addEventListener'
      && ts.isIdentifier(node.expression.expression)
      && node.expression.expression.text === 'window';
    const isHostAddWindowListener = methodName === 'addWindowListener';
    if (!isLegacyWindowAddEventListener && !isHostAddWindowListener) return;
    if (node.arguments.length < 2) return;

    const [eventArg, handlerArg] = node.arguments;
    if (!ts.isStringLiteral(eventArg) || eventArg.text !== eventName) return;
    if (!ts.isIdentifier(handlerArg) || handlerArg.text !== handlerName) return;
    found = true;
  });
  return found;
}

function assertResumeHandlerContract(sourceFile, handlerName) {
  // Modern shape: `onPageShow` is a thin window-listener delegator
  // that calls `runtimeController.handlePageShow(running)`, and the
  // actual predicate + immediate-tick logic lives on the controller's
  // `handlePageShow` method (likewise `onResume` -> `handleResume`).
  // Search both names so the structural intent is verified regardless
  // of which name carries the body.
  const controllerName = handlerName.replace(/^on/, 'handle');
  const candidateNames = controllerName === handlerName
    ? [handlerName]
    : [handlerName, controllerName];

  const handlerBodies = candidateNames.flatMap((name) => findHandlerBodyNodes(sourceFile, name));
  assertContract(
    handlerBodies.length > 0,
    SCRIPT_TAG,
    `sync module must define ${handlerName} handler (or its controller alias ${controllerName})`,
  );

  const callsResumePredicate = handlerBodies.some((body) =>
    hasIdentifierCall(body, 'shouldForceAndroidResumeResync')
    || hasIdentifierCall(body, 'shouldForceResumeResync'));
  assertContract(
    callsResumePredicate,
    SCRIPT_TAG,
    `${handlerName} must call shouldForceAndroidResumeResync() (directly or via closure alias)`,
  );

  const triggersImmediateTick = handlerBodies.some((body) =>
    hasScheduleImmediateTickTrueCall(body)
    || hasIdentifierCall(body, 'requestImmediateTick'));
  assertContract(
    triggersImmediateTick,
    SCRIPT_TAG,
    `${handlerName} must trigger immediate-tick request when Android resume gap threshold is crossed`,
  );
}

export function verifyAndroidBackgroundReliabilityContract({
  repoRoot = resolveRepoRootFromMeta(import.meta.url),
} = {}) {
  // The mobile sync runtime now lives in the folder-backed `sync/`
  // subtree. Reject the retired single-file facade so this verifier
  // keeps guarding the current topology.
  const legacySyncFilePath = path.join(repoRoot, 'app', 'src', 'lib', 'sync.ts');
  const syncDirPath = path.join(repoRoot, 'app', 'src', 'lib', 'sync');
  assertContract(
    !fs.existsSync(legacySyncFilePath),
    SCRIPT_TAG,
    'legacy app/src/lib/sync.ts must not exist',
  );
  assertContract(fs.existsSync(syncDirPath), SCRIPT_TAG, 'missing required directory: app/src/lib/sync/');
  const syncSourceFile = parseSyncSourceFile(repoRoot);

  assertContract(
    hasConstAlias(syncSourceFile, 'ANDROID_SUSPEND_RESYNC_GAP_MS', 'SYNC_LOOP_ANDROID_BACKGROUND_MS'),
    SCRIPT_TAG,
    'sync.ts must define ANDROID_SUSPEND_RESYNC_GAP_MS from SYNC_LOOP_ANDROID_BACKGROUND_MS',
  );
  assertContract(
    Boolean(findHandlerBodyNode(syncSourceFile, 'shouldForceAndroidResumeResync')),
    SCRIPT_TAG,
    'sync.ts must implement shouldForceAndroidResumeResync() helper',
  );
  assertContract(
    hasWindowEventListener(syncSourceFile, 'pageshow', 'onPageShow'),
    SCRIPT_TAG,
    'sync.ts must listen for pageshow resume signal',
  );
  assertContract(
    hasWindowEventListener(syncSourceFile, 'resume', 'onResume'),
    SCRIPT_TAG,
    'sync.ts must listen for resume signal',
  );

  assertResumeHandlerContract(syncSourceFile, 'onPageShow');
  assertResumeHandlerContract(syncSourceFile, 'onResume');

  return { ok: true };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runVerifierCli({
    scriptTag: SCRIPT_TAG,
    successMessage: 'Android background reliability contract checks passed.',
    run: () => verifyAndroidBackgroundReliabilityContract(),
  });
}
