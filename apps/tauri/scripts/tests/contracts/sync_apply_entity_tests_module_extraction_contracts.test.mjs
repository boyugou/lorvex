import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const facadePath = path.join(repoRoot, 'lorvex-sync/src/apply/tests/entity.rs');
const entityDir = path.join(repoRoot, 'lorvex-sync/src/apply/tests/entity');

function read(relativePath) {
  return fs.readFileSync(path.join(entityDir, relativePath), 'utf8');
}

function testNames(source) {
  return [...source.matchAll(/\n#\[test\]\s*\nfn\s+([a-zA-Z0-9_]+)\s*\(/g)].map((match) => match[1]);
}

function assertOwnsTests(source, expectedNames, label) {
  const names = testNames(source);
  assert.deepEqual(
    names.filter((name) => expectedNames.includes(name)).sort(),
    expectedNames.toSorted(),
    `${label} should own its expected test functions`,
  );
  assert.equal(new Set(names).size, names.length, `${label} test names should stay unique`);
}

