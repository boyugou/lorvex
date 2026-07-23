import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import ts from 'typescript';

import { repoRoot } from './shared.mjs';

const APP_SRC = path.join(repoRoot, 'app/src');
const SOURCE_EXTENSIONS = new Set(['.ts', '.tsx']);
const EXEMPT_RELATIVE_PATHS = new Set([
  'app/src/lib/query/usePreference.ts',
]);

function collectSourceFiles(dir, files = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith('.')) continue;
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      collectSourceFiles(fullPath, files);
      continue;
    }
    if (!entry.isFile()) continue;
    if (!SOURCE_EXTENSIONS.has(path.extname(entry.name))) continue;
    if (/\.(?:test|spec)\.tsx?$/.test(entry.name)) continue;
    files.push(fullPath);
  }
  return files;
}

function walk(node, visitor) {
  visitor(node);
  ts.forEachChild(node, (child) => walk(child, visitor));
}

function importedLocalNames(sourceFile, importedName) {
  const names = new Set();
  for (const statement of sourceFile.statements) {
    if (!ts.isImportDeclaration(statement)) continue;
    const bindings = statement.importClause?.namedBindings;
    if (!bindings || !ts.isNamedImports(bindings)) continue;
    for (const specifier of bindings.elements) {
      const originalName = specifier.propertyName?.text ?? specifier.name.text;
      if (originalName === importedName) {
        names.add(specifier.name.text);
      }
    }
  }
  return names;
}

function subtreeHasCallToAny(node, functionNames) {
  let found = false;
  walk(node, (child) => {
    if (found || !ts.isCallExpression(child)) return;
    if (ts.isIdentifier(child.expression) && functionNames.has(child.expression.text)) {
      found = true;
    }
  });
  return found;
}

function findDirectPreferenceUseQueryViolations(source, fileName = 'source.tsx') {
  const sourceFile = ts.createSourceFile(fileName, source, ts.ScriptTarget.Latest, true, ts.ScriptKind.TSX);
  const useQueryNames = importedLocalNames(sourceFile, 'useQuery');
  const getPreferenceNames = importedLocalNames(sourceFile, 'getPreference');
  if (useQueryNames.size === 0 || getPreferenceNames.size === 0) {
    return [];
  }

  const violations = [];
  walk(sourceFile, (node) => {
    if (!ts.isCallExpression(node)) return;
    if (!ts.isIdentifier(node.expression) || !useQueryNames.has(node.expression.text)) return;
    const [optionsArg] = node.arguments;
    if (!optionsArg || !subtreeHasCallToAny(optionsArg, getPreferenceNames)) return;
    const location = sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile));
    violations.push(`${fileName}:${location.line + 1}`);
  });
  return violations;
}

test('React preference reads go through usePreference instead of useQuery(getPreference)', () => {
  const offenders = [];
  for (const filePath of collectSourceFiles(APP_SRC)) {
    const relativePath = path.relative(repoRoot, filePath);
    if (EXEMPT_RELATIVE_PATHS.has(relativePath)) continue;
    const source = fs.readFileSync(filePath, 'utf8');
    offenders.push(...findDirectPreferenceUseQueryViolations(source, relativePath));
  }

  assert.deepEqual(
    offenders,
    [],
    `Single preference React queries must use app/src/lib/query/usePreference.ts:\n${offenders.join('\n')}`,
  );
});

test('preference query ownership scanner detects aliased direct useQuery(getPreference)', () => {
  const offenders = findDirectPreferenceUseQueryViolations(`
    import { useQuery as useTanstackQuery } from '@tanstack/react-query';
    import { getPreference as loadPreference } from './ipc';
    useTanstackQuery({
      queryKey: ['preference', 'timezone'],
      queryFn: ({ signal }) => loadPreference('timezone', signal),
    });
  `);
  assert.equal(offenders.length, 1);
});

test('preference query ownership scanner ignores non-query preference reads', () => {
  const offenders = findDirectPreferenceUseQueryViolations(`
    import { getPreference } from './ipc';
    export async function loadTimezone() {
      return getPreference('timezone');
    }
  `);
  assert.equal(offenders.length, 0);
});
