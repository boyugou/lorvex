import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from '../shared.mjs';
import { displayCommand, flattenBundle } from '../../../verify/verification_manifest.mjs';

const canonicalCalendarEventTypeRoadmap = [
  '# Roadmap',
  '- [x] Calendar event types: event, birthday, anniversary, memorial',
  '',
].join('\n');

const canonicalCalendarEventTypeSchema = [
  "CREATE TABLE calendar_events (event_type TEXT NOT NULL CHECK (event_type IN ('event', 'birthday', 'anniversary', 'memorial')));",
  "CREATE TABLE provider_calendar_events (event_type TEXT NOT NULL CHECK (event_type IN ('event', 'birthday', 'anniversary', 'memorial')));",
  '',
].join('\n');

function writeCalendarEventTypeContractFixtures(writeFixture) {
  writeFixture('ROADMAP.md', canonicalCalendarEventTypeRoadmap);
  writeFixture('lorvex-store/src/schema/001_schema.sql', canonicalCalendarEventTypeSchema);
}

test('source checkout onboarding distinguishes development from local install smoke', () => {
  const readme = fs.readFileSync(path.join(repoRoot, 'README.md'), 'utf8');
  const gettingStarted = fs.readFileSync(path.join(repoRoot, 'docs/setup/GETTING_STARTED.md'), 'utf8');
  const contributingGuide = fs.readFileSync(path.join(repoRoot, 'CONTRIBUTING.md'), 'utf8');

  assert.match(readme, /npm run -w app tauri:dev/, 'README should point source-checkout developers to the canonical tauri:dev loop');
  assert.match(gettingStarted, /npm run -w app tauri:dev/, 'Getting started guide should point source-checkout developers to the canonical tauri:dev loop');
  assert.match(gettingStarted, /local install smoke|packaging smoke/i, 'Getting Started should describe one-click scripts as install/package smoke, not the default dev loop');
  assert.match(gettingStarted, /local install smoke|packaging smoke/i, 'Getting started guide should describe one-click scripts as install/package smoke, not the default dev loop');
  assert.match(contributingGuide, /one-click scripts are only for local install|packaging smoke/i, 'Contributing guide should keep the install scripts scoped to local install/package validation');
  assert.doesNotMatch(readme, /Source checkout users \(dev\/test\): run the platform one-click script/i, 'README must not describe the install script as the source-checkout development loop');
});

test('onboarding docs exist as canonical entry points', () => {
  assert.ok(fs.existsSync(path.join(repoRoot, 'README.md')), 'README.md should exist');
  assert.ok(fs.existsSync(path.join(repoRoot, 'docs/setup/GETTING_STARTED.md')), 'GETTING_STARTED.md should exist');
  assert.ok(fs.existsSync(path.join(repoRoot, 'docs/setup/ASSISTANT_MCP_SETUP.md')), 'MCP setup guide should exist');
});

test('repository does not carry unowned git submodules', () => {
  assert.equal(
    fs.existsSync(path.join(repoRoot, '.gitmodules')),
    false,
    'Root .gitmodules should not exist unless submodule ownership, license, security, and update policy are documented',
  );

  const indexEntries = execFileSync('git', ['ls-files', '--stage'], {
    cwd: repoRoot,
    encoding: 'utf8',
  });
  const gitlinks = indexEntries
    .split('\n')
    .filter((line) => line.startsWith('160000 '))
    .map((line) => line.trim());

  assert.deepEqual(gitlinks, [], 'Gitlink entries should not be present in the index');
});

test('architecture docs describe lorvex-domain dependency boundary without stale zero-IO wording', () => {
  const activeDocs = [
    'README.md',
    'CLAUDE.md',
    'CONTRIBUTING.md',
    'docs/design/MULTI_SURFACE_ARCHITECTURE.md',
  ];

  for (const relativePath of activeDocs) {
    const doc = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
    assert.doesNotMatch(doc, /lorvex-domain[^\n]*zero IO deps/i, `${relativePath} should not claim lorvex-domain has zero IO deps`);
    assert.doesNotMatch(doc, /Must never depend on rusqlite/i, `${relativePath} should not forbid the feature-gated rusqlite binding`);
    assert.match(
      doc,
      /no unconditional IO\/storage deps|feature-gated rusqlite typed-id bindings|rusqlite.*feature.*typed-id SQL bindings/is,
      `${relativePath} should document the current lorvex-domain dependency boundary`,
    );
  }
});

test('assistant MCP setup documents Claude Code stdio config shape separately from Claude Desktop', () => {
  const setupGuide = fs.readFileSync(path.join(repoRoot, 'docs/setup/ASSISTANT_MCP_SETUP.md'), 'utf8');

  assert.match(setupGuide, /\*\*Claude Desktop\*\*[\s\S]*"mcpServers"[\s\S]*"command": "<path from Lorvex Settings>"/, 'setup guide should keep a Claude Desktop JSON example');
  assert.match(setupGuide, /\*\*Claude Code\*\*[\s\S]*"type": "stdio"[\s\S]*"command": "<path from Lorvex Settings>"/, 'setup guide should include Claude Code type: stdio');
  assert.doesNotMatch(setupGuide, /Claude Desktop \/ Claude Code/, 'setup guide should not share one JSON block for clients with different shapes');
  assert.match(setupGuide, /Claude Code \| Verified \| JSON config with `type: "stdio"`/, 'compatibility table should mention Claude Code stdio type');
});

test('doc governance verifier rejects prose-only instructions to create dated execution artifacts', async () => {
  const verifierModule = await import('../../../verify/doc_governance.mjs');
  assert.equal(typeof verifierModule.verifyDocGovernance, 'function', 'scripts/verify/doc_governance.mjs should export verifyDocGovernance for fixture tests');

  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'lorvex-doc-governance-'));
  const writeFixture = (relativePath, content) => {
    const absolutePath = path.join(fixtureRoot, relativePath);
    fs.mkdirSync(path.dirname(absolutePath), { recursive: true });
    fs.writeFileSync(absolutePath, content);
  };

  writeFixture('.gitignore', 'artifacts/manual-gates/\n');
  writeFixture('CLAUDE.md', 'docs/reference/REPO_FACTS.md\n');
  writeFixture('CONTRIBUTING.md', 'docs/reference/REPO_FACTS.md\n');
  writeFixture('GETTING_STARTED.md', '# Getting Started\n');
  writeFixture('README.md', '# Readme\n');
  writeCalendarEventTypeContractFixtures(writeFixture);
  writeFixture('docs/INDEX.md', '# Docs Index\n');
  writeFixture('docs/reference/REPO_FACTS.md', '# Repo Facts\n');
  writeFixture('docs/execution/ISSUE_LIFECYCLE.md', '# Issue lifecycle\n');
  writeFixture('docs/design/EXAMPLE.md', 'Document any deviation in a dated execution artifact before merge.\n');

  assert.throws(
    () => verifierModule.verifyDocGovernance({ repoRoot: fixtureRoot }),
    /dated execution artifact/i,
    'Doc governance verifier should reject prose that reintroduces dated execution artifacts',
  );
});

test('doc governance verifier rejects restored active backlog queues', async () => {
  const verifierModule = await import('../../../verify/doc_governance.mjs');
  assert.equal(typeof verifierModule.verifyDocGovernance, 'function', 'scripts/verify/doc_governance.mjs should export verifyDocGovernance for fixture tests');

  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'lorvex-doc-governance-backlog-'));
  const writeFixture = (relativePath, content) => {
    const absolutePath = path.join(fixtureRoot, relativePath);
    fs.mkdirSync(path.dirname(absolutePath), { recursive: true });
    fs.writeFileSync(absolutePath, content);
  };

  writeFixture('.gitignore', 'artifacts/manual-gates/\n');
  writeFixture('CLAUDE.md', 'docs/reference/REPO_FACTS.md\n');
  writeFixture('CONTRIBUTING.md', 'docs/reference/REPO_FACTS.md\n');
  writeFixture('GETTING_STARTED.md', '# Getting Started\n');
  writeFixture('README.md', '# Readme\n');
  writeCalendarEventTypeContractFixtures(writeFixture);
  writeFixture('docs/INDEX.md', '# Docs Index\n');
  writeFixture('docs/reference/REPO_FACTS.md', '# Repo Facts\n');
  writeFixture(
    'docs/execution/MASTER_BACKLOG.md',
    [
      '# Backlog',
      '### NOW (ready for implementation)',
      '| ID | Stream | Task | Exit Criteria | Status |',
      '|----|--------|------|---------------|--------|',
      '| B-001 | S1 | Completed item | Already shipped | Done |',
      '### NEXT (promote when executable capacity exists)',
      '| ID | Stream | Task | Exit Criteria |',
      '|----|--------|------|---------------|',
      '| B-002 | S1 | Active item | Merge tests |',
      '### LATER',
      '',
    ].join('\n'),
  );

  assert.throws(
    () => verifierModule.verifyDocGovernance({ repoRoot: fixtureRoot }),
    /MASTER_BACKLOG\.md is archived|active execution queue/i,
    'Doc governance verifier should reject restoring MASTER_BACKLOG as an active execution queue',
  );
});

test('doc governance verifier allows canonical prose that mentions Done outside active backlog status cells', async () => {
  const verifierModule = await import('../../../verify/doc_governance.mjs');
  assert.equal(typeof verifierModule.verifyDocGovernance, 'function', 'scripts/verify/doc_governance.mjs should export verifyDocGovernance for fixture tests');

  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'lorvex-doc-governance-active-done-prose-'));
  const writeFixture = (relativePath, content) => {
    const absolutePath = path.join(fixtureRoot, relativePath);
    fs.mkdirSync(path.dirname(absolutePath), { recursive: true });
    fs.writeFileSync(absolutePath, content);
  };

  writeFixture('.gitignore', 'artifacts/manual-gates/\n');
  writeFixture('CLAUDE.md', 'docs/reference/REPO_FACTS.md\n');
  writeFixture('CONTRIBUTING.md', 'docs/reference/REPO_FACTS.md\n');
  writeFixture('GETTING_STARTED.md', '# Getting Started\n');
  writeFixture('README.md', '# Readme\n');
  writeCalendarEventTypeContractFixtures(writeFixture);
  writeFixture('docs/INDEX.md', '# Docs Index\n');
  writeFixture('docs/reference/REPO_FACTS.md', '# Repo Facts\n');
  writeFixture('docs/execution/ISSUE_LIFECYCLE.md', '# Issue lifecycle\n');
  writeFixture('docs/design/DONE_STATE.md', '# Done-state UX\nDone when smoke checks pass.\n');

  assert.doesNotThrow(
    () => verifierModule.verifyDocGovernance({ repoRoot: fixtureRoot }),
    'Doc governance verifier should allow ordinary canonical prose that mentions Done without restoring an active backlog queue',
  );
});

test('canonical docs route deviations to canonical docs and issue evidence instead of dated execution artifacts', () => {
  const strategyDoc = fs.readFileSync(path.join(repoRoot, 'docs/design/PER_VIEW_CONTENT_STRATEGY.md'), 'utf8');

  assert.doesNotMatch(strategyDoc, /dated execution artifact/i, 'Canonical design docs must not direct people to repo-tracked dated execution artifacts');
  assert.match(strategyDoc, /canonical docs, linked issue comments, or manual-gate artifacts/i, 'Canonical design docs should point deviations to durable canonical docs or external evidence');
});

test('Apple mobile runtime status is retired from Tauri canonical docs and verification', () => {
  const featuresDoc = fs.readFileSync(path.join(repoRoot, 'docs/design/FEATURES.md'), 'utf8');
  const platformMatrix = fs.readFileSync(path.join(repoRoot, 'docs/design/PLATFORM_CAPABILITY_MATRIX.md'), 'utf8');
  const packageJson = JSON.parse(fs.readFileSync(path.join(repoRoot, 'package.json'), 'utf8'));
  const repoGovernanceCommands = flattenBundle('verify:repo-governance').map(displayCommand);

  assert.match(featuresDoc, /Mobile Runtime Direction \[PLANNED\]/, 'FEATURES should describe only future non-Apple mobile direction for Tauri');
  assert.match(featuresDoc, /iOS and iPadOS product work belongs to the Swift app in `apps\/apple`/);
  assert.doesNotMatch(platformMatrix, /\| iOS mobile runtime \|/, 'platform matrix must not list iOS as a Tauri runtime');
  assert.equal(packageJson.scripts['verify:repo-governance'], 'node scripts/verify/run_bundle.mjs verify:repo-governance', 'repo governance should use the typed bundle runner');
  assert.equal(repoGovernanceCommands.includes('npm run verify:ios-scaffold'), false, 'repo governance should not include a Tauri iOS scaffold gate');
  assert.equal(fs.existsSync(path.join(repoRoot, 'docs/execution/IPHONE_IMPLEMENTATION_CHECKLIST.md')), false);
});

test('scale resilience checklist references the manual MCP scale gate and canonical commands', () => {
  const checklist = fs.readFileSync(path.join(repoRoot, 'docs/execution/SCALE_RESILIENCE_CHECKLIST.md'), 'utf8');
  const contributingGuide = fs.readFileSync(path.join(repoRoot, 'CONTRIBUTING.md'), 'utf8');

  assert.match(checklist, /not wired to automated CI/i, 'scale checklist should describe the scale sweep as a manual, non-CI-wired gate');
  assert.doesNotMatch(checklist, /mcp-scale-report|mcp-scale-budget/, 'scale checklist must not reference a CI job name; Tauri has no CI-wired scale gate');
  assert.match(
    checklist,
    /scripts\/tests\/mcp\/integration\/query_bounds_and_scale\/bounded_query_cases\/high_cardinality\.ts/,
    'scale checklist should name the split high-cardinality test source',
  );
  assert.match(checklist, /scripts\/tests\/mcp\/integration\.test\.ts/, 'scale checklist should still name the integration harness entrypoint');
  assert.doesNotMatch(
    checklist,
    /cd\s+mcp-server\s+&&\s+npx\s+tsc/i,
    'scale checklist must not run TypeScript commands inside the Rust-only MCP crate',
  );
  for (const command of [
    'npm run verify:ci-typecheck',
    'npm run test:mcp:integration',
    'npm run benchmark:mcp:scale -- --dataset=1000,10000',
    'cargo check --manifest-path mcp-server/Cargo.toml',
    'cargo clippy --manifest-path mcp-server/Cargo.toml -- -D warnings',
    'cargo test --manifest-path mcp-server/Cargo.toml',
  ]) {
    assert.match(checklist, new RegExp(command.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')), `scale checklist should include ${command}`);
  }
  assert.match(contributingGuide, /cargo check --manifest-path mcp-server\/Cargo\.toml/, 'CONTRIBUTING should keep the canonical Rust MCP check command');
});

test('retired iPhone and iCloud docs stay removed from Tauri canonical docs', () => {
  const roadmap = fs.readFileSync(path.join(repoRoot, 'ROADMAP.md'), 'utf8');

  assert.match(roadmap, /all entities wired through sync/i, 'ROADMAP should track all-entity sync wiring as shipped');
  assert.doesNotMatch(roadmap, /iCloud CloudKit sync \(push\/pull/i);
  assert.equal(fs.existsSync(path.join(repoRoot, 'docs/execution/IPHONE_IMPLEMENTATION_CHECKLIST.md')), false);
  assert.equal(fs.existsSync(path.join(repoRoot, 'docs/design/ICLOUD_SYNC.md')), false);
});

test('roadmap keeps live status in canonical docs instead of requiring dated decision registers', () => {
  const roadmap = fs.readFileSync(path.join(repoRoot, 'ROADMAP.md'), 'utf8');
  assert.match(roadmap, /Shipped|In Progress|Not Started/i, 'ROADMAP should track live status');
  assert.doesNotMatch(roadmap, /REASONABILITY_REVIEW_2026-03-01/, 'ROADMAP must not require a dated reasonability review as the live issue register');
});

test('CLAUDE guide uses generated facts, canonical governance bundle naming, and tool-agnostic edit guidance', () => {
  const claudeGuide = fs.readFileSync(path.join(repoRoot, 'CLAUDE.md'), 'utf8');
  const contributingGuide = fs.readFileSync(path.join(repoRoot, 'CONTRIBUTING.md'), 'utf8');
  // Verification commands live in CONTRIBUTING.md (CLAUDE.md references it for coding standards)
  assert.match(claudeGuide, /CONTRIBUTING\.md/, 'CLAUDE should reference CONTRIBUTING.md for coding standards');
  assert.match(contributingGuide, /npm run test:mcp:migrations/, 'CONTRIBUTING should include Rust MCP migration coverage');
  assert.match(contributingGuide, /cargo check --manifest-path mcp-server\/Cargo\.toml/, 'CONTRIBUTING should include Rust MCP cargo check');
  assert.match(contributingGuide, /cargo clippy --manifest-path mcp-server\/Cargo\.toml -- -D warnings/, 'CONTRIBUTING should include Rust MCP clippy');
  assert.match(claudeGuide, /docs\/execution\/templates\//, 'CLAUDE should route reusable execution templates into docs/execution/templates/');
  assert.match(claudeGuide, /docs\/reference\/REPO_FACTS\.md/, 'CLAUDE should defer mutable repo facts to REPO_FACTS');
  assert.match(contributingGuide, /scripts\/lib\//, 'CONTRIBUTING should describe scripts/lib as part of the internal automation layout');
  assert.match(contributingGuide, /verify:repo-governance/, 'CONTRIBUTING should use the canonical repo-governance verifier bundle name');
  assert.match(contributingGuide, /npm run verify:mcp-runtime-bundle/, 'CONTRIBUTING should document prepared MCP runtime bundle verification separately from the installed-checkout governance bundle');
  assert.doesNotMatch(claudeGuide, /REASONABILITY_REVIEW_2026-03-01/, 'CLAUDE must not require a dated decision doc as standing guidance');
  assert.doesNotMatch(claudeGuide, /\buse Write to rewrite the entire file\b/i, 'CLAUDE must not rely on a stale Write-tool instruction');
  assert.doesNotMatch(claudeGuide, /009_calendar_event_timezone\.sql/, 'CLAUDE should not hard-code the stale last migration filename');
  assert.doesNotMatch(claudeGuide, /RFC-001 through RFC-006/, 'CLAUDE should not hard-code a stale RFC range');
});
