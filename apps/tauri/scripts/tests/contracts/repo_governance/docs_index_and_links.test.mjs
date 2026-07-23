import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from '../shared.mjs';

test('docs index and canonical workflow docs isolate historical material behind archive README only', () => {
  const docsIndex = fs.readFileSync(path.join(repoRoot, 'docs/INDEX.md'), 'utf8');
  const inventory = docsIndex.split('<!-- DOC_INVENTORY:START -->')[1] ?? '';
  const claude = fs.readFileSync(path.join(repoRoot, 'CLAUDE.md'), 'utf8');
  const architecture = fs.readFileSync(path.join(repoRoot, 'docs/design/ARCHITECTURE.md'), 'utf8');

  assert.match(docsIndex, /\[archive\/README\.md\]\(archive\/README\.md\)/, 'Docs index should expose archive through README only');
  assert.ok(!fs.existsSync(path.join(repoRoot, 'docs/execution/MASTER_BACKLOG.md')), 'Active MASTER_BACKLOG must stay archived; GitHub Issues hold live backlog state');
  assert.doesNotMatch(docsIndex, /decisions\//i, 'Docs index must not directly surface decisions paths');
  assert.doesNotMatch(docsIndex, /rfcs\//i, 'Docs index must not directly surface RFC paths');
  assert.match(docsIndex, /ROADMAP \(status\) → Architecture → .*Data Model → the relevant design doc/i, 'Docs index should route builders through canonical design docs');
  assert.match(docsIndex, /\[\.\.\/README\.md\]\(\.\.\/README\.md\)/, 'Docs index should surface the top-level README as an entrypoint');
  assert.match(docsIndex, /GETTING_STARTED\.md/, 'Docs index should surface GETTING_STARTED as an entrypoint');
  assert.match(docsIndex, /\[\.\.\/CONTRIBUTING\.md\]\(\.\.\/CONTRIBUTING\.md\)/, 'Docs index should surface CONTRIBUTING as an entrypoint');
  assert.doesNotMatch(inventory, /^### archive\//m, 'docs/INDEX inventory should not expose archive/ as a primary auto-generated reading path');
  assert.doesNotMatch(claude, /docs\/decisions\/|docs\/rfcs\//i, 'CLAUDE should not send implementers into historical docs');
  assert.doesNotMatch(architecture, /\.\.\/rfcs\//i, 'Canonical architecture docs must not link directly to archive/RFC material');
});

test('markdown link verifier covers extra markdown files and the PR template in addition to canonical docs', async () => {
  const verifierModule = await import('../../../verify/markdown_links.mjs');
  assert.equal(typeof verifierModule.verifyMarkdownLinks, 'function', 'scripts/verify/markdown_links.mjs should export verifyMarkdownLinks for fixture tests');

  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'lorvex-markdown-links-'));
  const writeFixture = (relativePath, content) => {
    const absolutePath = path.join(fixtureRoot, relativePath);
    fs.mkdirSync(path.dirname(absolutePath), { recursive: true });
    fs.writeFileSync(absolutePath, content);
  };

  writeFixture('CLAUDE.md', '# Claude\n');
  writeFixture('CONTRIBUTING.md', '# Contributing\n');
  writeFixture('GETTING_STARTED.md', '# Getting Started\n');
  writeFixture('README.md', '# Readme\n');
  writeFixture('README.zh-CN.md', '# README ZH\nSee [Broken README link](docs/MISSING.md).\n');
  writeFixture('ROADMAP.md', '# Roadmap\n');
  writeFixture('.github/PULL_REQUEST_TEMPLATE.md', '# PR\nSee [Broken PR link](../docs/ALSO_MISSING.md).\n');
  writeFixture('docs/INDEX.md', '# Docs\n');

  assert.throws(
    () => verifierModule.verifyMarkdownLinks({ repoRoot: fixtureRoot }),
    /MISSING\.md|ALSO_MISSING\.md/i,
    'Markdown link verifier should fail when extra markdown files or the PR template contain broken repo-local links',
  );
});

test('markdown link verifier covers issue-template yaml GitHub blob URLs', async () => {
  const verifierModule = await import('../../../verify/markdown_links.mjs');
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'lorvex-yaml-links-'));
  const writeFixture = (relativePath, content) => {
    const absolutePath = path.join(fixtureRoot, relativePath);
    fs.mkdirSync(path.dirname(absolutePath), { recursive: true });
    fs.writeFileSync(absolutePath, content);
  };

  writeFixture('.git/config', '[remote "origin"]\n\turl = git@github.com:boyugou/ai-native-todo.git\n');
  writeFixture('docs/INDEX.md', '# Docs\n');
  writeFixture('.github/ISSUE_TEMPLATE/config.yml', [
    'blank_issues_enabled: true',
    'contact_links:',
    '  - name: Documentation',
    '    url: https://github.com/boyugou/other-repo/blob/main/docs/INDEX.md',
    '    about: Wrong repo slug must fail',
    '  - name: Missing docs',
    '    url: https://github.com/boyugou/ai-native-todo/blob/main/docs/MISSING.md',
    '    about: Missing path must fail',
    '',
  ].join('\n'));
  writeFixture('.github/workflows/check.yml', [
    'name: Check',
    'on: pull_request',
    'jobs:',
    '  docs:',
    '    runs-on: ubuntu-latest',
    '    steps:',
    '      - name: Docs',
    '        url: https://github.com/boyugou/other-repo/blob/main/docs/INDEX.md',
    '',
  ].join('\n'));

  assert.throws(
    () => verifierModule.verifyMarkdownLinks({ repoRoot: fixtureRoot }),
    /expected GitHub repo boyugou\/ai-native-todo|MISSING\.md/i,
    'YAML GitHub blob URLs under .github should stay aligned with the current repo and real files',
  );
});

test('docs governance rejects undefined design status tags', async () => {
  const governanceModule = await import('../../../verify/doc_governance.mjs');
  assert.deepEqual(
    governanceModule.collectUndefinedDesignStatusTags('### Inbox [CUT]\n### Conversational Review [UPDATED]\n'),
    ['UPDATED'],
    'Only canonical design status tags should be accepted',
  );
});

// Translated READMEs were removed in #910; MCP-generic wording is
// only enforced on the canonical README.md now.
test('README describes MCP clients generically instead of hard-coding specific assistant brands', () => {
  const text = fs.readFileSync(path.join(repoRoot, 'README.md'), 'utf8');
  assert.match(text, /MCP/i, 'README.md missing MCP client wording');
});

test('README and docs index point verification readers to canonical npm scripts', () => {
  const readme = fs.readFileSync(path.join(repoRoot, 'README.md'), 'utf8');
  const docsIndex = fs.readFileSync(path.join(repoRoot, 'docs', 'INDEX.md'), 'utf8');

  assert.match(readme, /CONTRIBUTING\.md/, 'README should point contributors to CONTRIBUTING for verification commands');
  assert.doesNotMatch(readme, /verify:docs-index --check/, 'README should not publish stale direct verifier invocations');
  assert.match(docsIndex, /npm run verify:docs-index/, 'docs index generator note should use the canonical npm verifier script');
  assert.doesNotMatch(docsIndex, /verify:docs-index --check/, 'docs index should not show the stale direct verifier command');
});
