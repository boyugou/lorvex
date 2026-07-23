import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import ts from 'typescript';

import { repoRoot } from './shared.mjs';

const APP_SRC_ROOT = 'app/src';
const ALLOWED_FALLBACK = {
  file: 'app/src/lib/errors/errorLogging.ts',
  method: 'error',
  functionName: 'emitClientErrorLogFallback',
};

function listSourceFiles(dir) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    const absolutePath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...listSourceFiles(absolutePath));
      continue;
    }
    if (/\.(?:ts|tsx)$/.test(entry.name) && !/\.test\.(?:ts|tsx)$/.test(entry.name)) {
      files.push(absolutePath);
    }
  }

  return files;
}

function sourceKind(filePath) {
  return filePath.endsWith('.tsx') ? ts.ScriptKind.TSX : ts.ScriptKind.TS;
}

function nearestFunctionName(node) {
  let current = node.parent;
  while (current) {
    if (ts.isFunctionDeclaration(current) && current.name) {
      return current.name.text;
    }
    if (
      ts.isVariableDeclaration(current)
      && ts.isIdentifier(current.name)
      && current.initializer
      && (ts.isArrowFunction(current.initializer) || ts.isFunctionExpression(current.initializer))
    ) {
      return current.name.text;
    }
    current = current.parent;
  }
  return null;
}

function isWindowConsoleExpression(expression) {
  if (!ts.isPropertyAccessExpression(expression) || expression.name.text !== 'console') return false;
  return (
    ts.isIdentifier(expression.expression)
    && (expression.expression.text === 'window' || expression.expression.text === 'globalThis')
  );
}

function isConsoleObjectExpression(expression, consoleObjectAliases) {
  if (ts.isIdentifier(expression)) return consoleObjectAliases.has(expression.text);
  return isWindowConsoleExpression(expression);
}

function methodFromConsoleMemberExpression(expression, consoleObjectAliases) {
  if (ts.isPropertyAccessExpression(expression)) {
    if (!isConsoleObjectExpression(expression.expression, consoleObjectAliases)) return null;
    return expression.name.text;
  }
  if (ts.isElementAccessExpression(expression)) {
    if (!isConsoleObjectExpression(expression.expression, consoleObjectAliases)) return null;
    const argument = expression.argumentExpression;
    if (!argument || !ts.isStringLiteralLike(argument)) return null;
    return argument.text;
  }
  return null;
}

function consoleMethodFromCall(node, consoleObjectAliases, consoleMethodAliases) {
  if (!ts.isCallExpression(node)) return null;
  const expression = node.expression;
  if (ts.isIdentifier(expression)) {
    return consoleMethodAliases.get(expression.text) ?? null;
  }
  return methodFromConsoleMemberExpression(expression, consoleObjectAliases);
}

function registerConsoleAliases(node, consoleObjectAliases, consoleMethodAliases) {
  if (!ts.isVariableDeclaration(node) || !node.initializer) return;

  if (ts.isIdentifier(node.name)) {
    if (isConsoleObjectExpression(node.initializer, consoleObjectAliases)) {
      consoleObjectAliases.add(node.name.text);
      return;
    }
    const method = methodFromConsoleMemberExpression(node.initializer, consoleObjectAliases);
    if (method) {
      consoleMethodAliases.set(node.name.text, method);
    }
    return;
  }

  if (
    !ts.isObjectBindingPattern(node.name)
    || !isConsoleObjectExpression(node.initializer, consoleObjectAliases)
  ) {
    return;
  }

  for (const element of node.name.elements) {
    if (!ts.isIdentifier(element.name)) continue;
    const propertyName = element.propertyName;
    if (propertyName && !ts.isIdentifier(propertyName) && !ts.isStringLiteralLike(propertyName)) {
      continue;
    }
    consoleMethodAliases.set(element.name.text, propertyName?.text ?? element.name.text);
  }
}

function collectConsoleCalls(filePath) {
  const source = fs.readFileSync(filePath, 'utf8');
  const sourceFile = ts.createSourceFile(
    filePath,
    source,
    ts.ScriptTarget.Latest,
    true,
    sourceKind(filePath),
  );
  const calls = [];
  const consoleObjectAliases = new Set(['console']);
  const consoleMethodAliases = new Map();

  function visit(node) {
    registerConsoleAliases(node, consoleObjectAliases, consoleMethodAliases);
    const consoleMethod = consoleMethodFromCall(node, consoleObjectAliases, consoleMethodAliases);
    if (consoleMethod) {
      const { line } = sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile));
      calls.push({
        file: path.relative(repoRoot, filePath),
        line: line + 1,
        method: consoleMethod,
        functionName: nearestFunctionName(node),
      });
    }
    ts.forEachChild(node, visit);
  }

  visit(sourceFile);
  return calls;
}

test('production frontend direct console output stays limited to the client-error-log fallback sink', () => {
  const appSrcRoot = path.join(repoRoot, APP_SRC_ROOT);
  const calls = listSourceFiles(appSrcRoot).flatMap(collectConsoleCalls);

  assert.deepEqual(
    calls,
    [
      {
        ...ALLOWED_FALLBACK,
        line: calls[0]?.line,
      },
    ],
    `unexpected frontend console calls:\n${JSON.stringify(calls, null, 2)}`,
  );
  assert.equal(
    calls[0]?.functionName,
    ALLOWED_FALLBACK.functionName,
    'the remaining frontend console fallback must live behind an explicitly named helper',
  );
});

test('frontend console scanner detects member, bracket, and alias output forms', () => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'lorvex-console-contract-'));
  const fixturePath = path.join(tempDir, 'console-fixture.ts');
  fs.writeFileSync(
    fixturePath,
    `
      export function fixture() {
        window.console.error('window member');
        globalThis.console.warn('global member');
        console['info']('bracket member');
        const logger = console;
        logger.debug('object alias');
        const fail = console.error;
        fail('method alias');
        const { warn } = console;
        warn('destructured method alias');
      }
    `,
    'utf8',
  );

  const calls = collectConsoleCalls(fixturePath);

  assert.deepEqual(
    calls.map((call) => call.method),
    ['error', 'warn', 'info', 'debug', 'error', 'warn'],
  );
});
