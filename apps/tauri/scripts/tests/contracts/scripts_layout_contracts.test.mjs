import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

function read(relPath) {
  return fs.readFileSync(path.join(repoRoot, relPath), 'utf8');
}

test('scripts directory documents its layout and keeps SQL fixtures out of the top level', () => {
  const scriptsRoot = path.join(repoRoot, 'scripts');
  const topLevelSqlFiles = fs
    .readdirSync(scriptsRoot, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith('.sql'))
    .map((entry) => entry.name)
    .sort();
  const scriptsReadmePath = path.join(scriptsRoot, 'README.md');
  const claudeGuide = read('CLAUDE.md');
  const contributingGuide = read('CONTRIBUTING.md');

  assert.deepEqual(topLevelSqlFiles, [], 'SQL seed fixtures should live under scripts/fixtures, not directly under scripts/');
  assert.equal(fs.existsSync(scriptsReadmePath), true, 'scripts/README.md should document script placement rules');

  const scriptsReadme = fs.readFileSync(scriptsReadmePath, 'utf8');
  assert.match(scriptsReadme, /Top-level files/i, 'scripts/README.md should describe top-level script rules');
  assert.match(scriptsReadme, /scripts\/fixtures\/seed\.sql/, 'scripts/README.md should point to the seed SQL fixture');
  assert.match(scriptsReadme, /scripts\/fixtures\/seed_scale\.sql/, 'scripts/README.md should point to the scale seed SQL fixture');
  assert.doesNotMatch(claudeGuide, /each `scripts\/` subdir README|each subdir README/i, 'CLAUDE.md should not point to nonexistent per-subdir READMEs');
  assert.match(claudeGuide, /scripts\/README\.md/, 'CLAUDE.md should point readers to scripts/README.md');
  assert.match(contributingGuide, /scripts\/fixtures\//, 'CONTRIBUTING should document where non-entrypoint script fixtures live');
});

test('repository docs reference moved SQL seed fixture paths', () => {
  const checkedDocs = [
    'CONTRIBUTING.md',
    'CLAUDE.md',
    'docs/execution/SCALE_RESILIENCE_CHECKLIST.md',
    'scripts/README.md',
  ];

  for (const relPath of checkedDocs) {
    const source = read(relPath);
    assert.doesNotMatch(source, /\bscripts\/seed(?:_scale)?\.sql\b/, `${relPath} should not reference top-level SQL seed fixtures`);
  }

  assert.match(
    read('docs/execution/SCALE_RESILIENCE_CHECKLIST.md'),
    /scripts\/fixtures\/seed_scale\.sql/,
    'scale resilience checklist should use the moved scale seed fixture',
  );
  assert.equal(fs.existsSync(path.join(repoRoot, 'docs/appstore/screenshots.md')), false);
});
