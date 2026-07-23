import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

function collectProductionTsxFiles(dir) {
  const files = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...collectProductionTsxFiles(fullPath));
      continue;
    }
    if (!entry.isFile() || !entry.name.endsWith('.tsx') || entry.name.endsWith('.test.tsx')) {
      continue;
    }
    files.push(fullPath);
  }
  return files;
}

function lineNumberForOffset(source, offset) {
  return source.slice(0, offset).split('\n').length;
}

test('all Toggle call sites provide an accessible switch name', () => {
  const files = collectProductionTsxFiles(path.join(repoRoot, 'app', 'src'));
  const unnamedToggleCallSites = [];

  for (const file of files) {
    const source = fs.readFileSync(file, 'utf8');
    for (const match of source.matchAll(/<Toggle\b[\s\S]*?\/>/g)) {
      const callSite = match[0];
      if (/\b(?:label|ariaLabel|ariaLabelledBy)=/.test(callSite)) {
        continue;
      }
      unnamedToggleCallSites.push(`${path.relative(repoRoot, file)}:${lineNumberForOffset(source, match.index)}`);
    }
  }

  assert.deepEqual(unnamedToggleCallSites, []);
});
