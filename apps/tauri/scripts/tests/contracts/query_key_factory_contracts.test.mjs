import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const appSrc = path.join(repoRoot, 'app/src');

const allowedRelativeFiles = new Set([
  'app/src/lib/query/queryKeyFactory.ts',
]);

function collectSourceFiles(dir) {
  const files = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...collectSourceFiles(full));
      continue;
    }
    if (!entry.isFile() || !/\.tsx?$/.test(entry.name)) continue;
    if (/\.(?:test|logic\.test|runtime\.test)\.tsx?$/.test(entry.name)) continue;
    files.push(full);
  }
  return files;
}

function stripComments(source) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/.*$/gm, '$1');
}

test('production app query keys are built through canonical factories', () => {
  const violations = [];
  const rawQueryKeyProperty = /\bqueryKey\s*:\s*\[/g;
  const rawQueryClientTuple = /\b(?:cancelQueries|ensureQueryData|fetchQuery|getQueriesData|getQueryData|invalidateQueries|isFetching|prefetchQuery|refetchQueries|removeQueries|resetQueries|setQueriesData|setQueryData|setQueryDefaults)\s*\(\s*\[/g;

  for (const file of collectSourceFiles(appSrc)) {
    const relative = path.relative(repoRoot, file);
    if (allowedRelativeFiles.has(relative)) continue;

    const source = stripComments(fs.readFileSync(file, 'utf8'));
    for (const pattern of [rawQueryKeyProperty, rawQueryClientTuple]) {
      pattern.lastIndex = 0;
      let match;
      while ((match = pattern.exec(source)) !== null) {
        const line = source.slice(0, match.index).split('\n').length;
        violations.push(`${relative}:${line}: ${match[0]}`);
      }
    }
  }

  assert.deepEqual(violations, []);
});
