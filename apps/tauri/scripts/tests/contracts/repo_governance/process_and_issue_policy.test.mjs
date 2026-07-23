import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from '../shared.mjs';
import { displayCommand, flattenBundle } from '../../../verify/verification_manifest.mjs';

function validCloseoutComment({ repoSlug = 'example/repo', commit = 'abcdef0' } = {}) {
  return `## Outcome
Closed the scoped cleanup.

## What changed
- Removed the stale wrapper.

## Verification
- npm run verify:repo-governance

## Risk / follow-up
- None.

- Evidence permalink: https://github.com/${repoSlug}/issues/123#issuecomment-456
- Commit: ${commit}
`;
}

test('process norms avoid quota-driven retrospectives and repo-doc evidence drift', () => {
  const claudeGuide = fs.readFileSync(path.join(repoRoot, 'CLAUDE.md'), 'utf8');
  const issueLifecycle = fs.readFileSync(path.join(repoRoot, 'docs', 'execution', 'ISSUE_LIFECYCLE.md'), 'utf8');
  const retrospectiveTemplate = fs.readFileSync(path.join(repoRoot, 'docs', 'execution', 'templates', 'process-retrospective.md.tmpl'), 'utf8');

  assert.doesNotMatch(claudeGuide, /every 4 implementation cycles|once per active workday/i, 'CLAUDE must not mandate quota-driven process artifacts');
  assert.doesNotMatch(issueLifecycle, /every 4 implementation cycles|once per active workday/i, 'Issue lifecycle must not mandate quota-driven process artifacts');
  assert.doesNotMatch(retrospectiveTemplate, /linked to issue `#81`/i, 'Process retrospective template must not hard-code a single tracker issue');
  assert.match(claudeGuide, /issue\/PR comments/i, 'Evidence notes should stay on issue/PR comments');
  assert.match(issueLifecycle, /docs\/execution\/templates\/process-retrospective\.md\.tmpl/, 'Issue lifecycle should point to the template directory, not the execution root');
  assert.match(issueLifecycle, /issue\/PR comment draft or local scratch aid/i, 'Issue lifecycle should route process-retrospective output to issue/PR or local scratch by default');
  assert.doesNotMatch(issueLifecycle, /standalone durable note/i, 'Issue lifecycle should not invite new standalone repo-tracked retrospective notes');
});

test('intake norms use needs-design instead of question or discussion issue terminology', () => {
  const contributingGuide = fs.readFileSync(path.join(repoRoot, 'CONTRIBUTING.md'), 'utf8');

  assert.match(contributingGuide, /needs-design/, 'Contributing guide should point unclear work to needs-design');
  assert.doesNotMatch(contributingGuide, /question issue|discussion issue/i, 'Contributing guide should retire question/discussion issue terminology');
});

test('issue-first policy is consistent across canonical contributor and agent docs', () => {
  const contributingGuide = fs.readFileSync(path.join(repoRoot, 'CONTRIBUTING.md'), 'utf8');
  const claudeGuide = fs.readFileSync(path.join(repoRoot, 'CLAUDE.md'), 'utf8');

  assert.match(contributingGuide, /Before starting non-trivial implementation:/, 'Contributing should scope issue-first to non-trivial implementation');
  assert.match(contributingGuide, /actionable task originates from chat\/user feedback and is non-trivial/i, 'Contributing should treat non-trivial chat/user work as issue-first');
  assert.match(claudeGuide, /Every non-trivial implementation must map to a GitHub issue/i, 'CLAUDE should scope issue-first to non-trivial implementation');
  assert.doesNotMatch(claudeGuide, /Every actionable user request must map to a GitHub issue before implementation/i, 'CLAUDE should not impose a stricter every-request rule than the rest of the repo');
});

test('script layout docs include scripts/lib and package scripts avoid legacy verifier aliases', () => {
  const contributingGuide = fs.readFileSync(path.join(repoRoot, 'CONTRIBUTING.md'), 'utf8');
  const packageJson = JSON.parse(fs.readFileSync(path.join(repoRoot, 'package.json'), 'utf8'));
  const repoGovernanceCommands = flattenBundle('verify:repo-governance').map(displayCommand);

  assert.match(contributingGuide, /scripts\/lib\//, 'Contributing guide should describe scripts/lib as an internal automation directory');
  assert.equal(packageJson.scripts['verify:docs-bundle'], undefined, 'package.json should not keep the legacy verify:docs-bundle alias');
  assert.equal(packageJson.scripts['verify:docs-bundle:fresh'], undefined, 'package.json should not keep the legacy verify:docs-bundle:fresh alias');
  assert.equal(packageJson.scripts['verify:platform-governance-contract:new-only'], undefined, 'package.json should not keep the unused new-only platform governance alias');
  assert.equal(packageJson.scripts['verify:frontend-typecheck'], undefined, 'package.json should not keep an orphaned frontend typecheck wrapper alias');
  assert.equal(fs.existsSync(path.join(repoRoot, 'scripts', 'verify', 'frontend_typecheck.mjs')), false, 'orphaned frontend typecheck wrapper file should not exist');
  assert.equal(packageJson.scripts['verify:repo-governance'], 'node scripts/verify/run_bundle.mjs verify:repo-governance', 'repo governance should use the typed bundle runner');
  assert.equal(repoGovernanceCommands.includes('npm run -w app typecheck'), true, 'repo governance should call the frontend typecheck command directly');
});

test('issue lifecycle close-out evidence is executable instead of prose-only', async () => {
  const verifierModule = await import('../../../verify/issue_lifecycle_evidence.mjs');
  const contributingGuide = fs.readFileSync(path.join(repoRoot, 'CONTRIBUTING.md'), 'utf8');
  const issueLifecycle = fs.readFileSync(path.join(repoRoot, 'docs', 'execution', 'ISSUE_LIFECYCLE.md'), 'utf8');
  const packageJson = JSON.parse(fs.readFileSync(path.join(repoRoot, 'package.json'), 'utf8'));
  const repoGovernanceCommands = flattenBundle('verify:repo-governance').map(displayCommand);
  const repoSlug = verifierModule.resolveGitHubRepoSlug({ repoRoot });
  const reachableCommit = verifierModule.resolveOriginMainCommit({ repoRoot });
  const evidenceContext = {
    repoSlug,
    verifyCommit: (commit) => verifierModule.verifyCommitReachableFromOriginMain({ repoRoot, commit }),
  };
  const closeoutBody = ({ evidenceRepoSlug = repoSlug, commit = reachableCommit, fragment = 'issuecomment-456' } = {}) => `## Outcome
Closed the scoped cleanup.

## What changed
- Removed the stale wrapper.

## Verification
- npm run verify:repo-governance

## Risk / follow-up
- None.

- Evidence permalink: https://github.com/${evidenceRepoSlug}/issues/123#${fragment}
- Commit: ${commit}
`;

  assert.equal(typeof verifierModule.verifyCloseoutComment, 'function', 'issue lifecycle verifier should export verifyCloseoutComment for fixture tests');
  assert.equal(packageJson.scripts['verify:issue-lifecycle-evidence'], 'node scripts/verify/issue_lifecycle_evidence.mjs', 'package.json should expose the issue lifecycle evidence verifier without hardcoded mode flags');
  assert.equal(repoGovernanceCommands.includes('npm run verify:issue-lifecycle-evidence -- --recent-closed 5'), true, 'repo governance should validate recent closed issue evidence, not just the docs contract');
  assert.match(issueLifecycle, /Evidence permalink/, 'Issue lifecycle should require evidence permalinks for close-out');
  assert.match(issueLifecycle, /npm run verify:issue-lifecycle-evidence/, 'Issue lifecycle should document the executable close-out verifier');
  assert.match(issueLifecycle, /--contract-only/, 'Issue lifecycle should distinguish docs-contract mode from real issue evidence validation');
  assert.match(contributingGuide, /npm run verify:issue-lifecycle-evidence/, 'Contributing should point issue owners to the close-out verifier');

  assert.throws(
    () => verifierModule.verifyCloseoutComment('Resolved in commit abcdef0. Tests passed.'),
    /Outcome|Evidence permalink|close-out/i,
    'prose-only close-out comments should fail the executable evidence contract',
  );
  assert.throws(
    () => verifierModule.verifyCloseoutComment(`## Outcome
Closed the scoped cleanup.

## What changed
- Removed the stale wrapper.

## Verification
- npm run verify:repo-governance

## Risk / follow-up
- None.

- Evidence permalink: https://github.com/example/repo/issues/123
- Commit: ${reachableCommit}
`),
    /comment permalink/i,
    'bare issue or PR URLs should not satisfy the evidence permalink contract',
  );

  assert.throws(
    () => verifierModule.verifyCloseoutComment(closeoutBody({ evidenceRepoSlug: 'example/repo' }), { evidenceContext }),
    /must belong to this repository/i,
    'off-repo issue or PR comment URLs should not satisfy the evidence permalink contract',
  );

  assert.throws(
    () => verifierModule.verifyCloseoutComment(closeoutBody({ commit: '0000000' }), { evidenceContext }),
    /local git commit|origin\/main/i,
    'fabricated commit shas should not satisfy the executable evidence contract',
  );

  assert.doesNotThrow(
    () => verifierModule.verifyCloseoutComment(closeoutBody(), { evidenceContext }),
    'structured close-out evidence with a same-repo permalink and reachable commit should satisfy the verifier',
  );

  assert.throws(
    () => verifierModule.verifyIssuePayload({
      number: 42,
      state: 'CLOSED',
      comments: [{ body: 'Closed in abcdef0. Tests passed.' }],
    }),
    /no valid structured close-out evidence comment/i,
    'closed issue payloads without structured close-out evidence should fail',
  );

  assert.doesNotThrow(() => verifierModule.verifyIssuePayload({
    number: 43,
    state: 'CLOSED',
    comments: [{
      body: closeoutBody(),
    }],
  }, { evidenceContext }), 'closed issue payloads with structured close-out evidence should pass');

  const validClosedPayload = {
    number: 44,
    state: 'CLOSED',
    comments: [{
      body: closeoutBody(),
    }],
  };
  const defaultResult = verifierModule.verifyIssueLifecycleEvidence({
    argv: [],
    readRecentClosedIssueNumbers: () => ['44'],
    readIssuePayload: () => validClosedPayload,
    evidenceContext,
  });
  assert.equal(defaultResult.mode, 'recent-closed', 'bare issue lifecycle verifier should scan recent closed issues by default');
});

test('recent closed mode selects the newest closedAt issues before applying the requested limit', async () => {
  const verifierModule = await import('../../../verify/issue_lifecycle_evidence.mjs');
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'lorvex-recent-closed-'));
  const fakeGhPath = path.join(tempDir, 'gh');
  const fakeClosedIssues = [
    { number: 4305, closed_at: '2026-05-01T00:00:00Z', updated_at: '2026-05-20T00:00:00Z' },
    { number: 4304, closed_at: '2026-05-02T00:00:00Z', updated_at: '2026-05-19T00:00:00Z' },
    { number: 4302, closed_at: '2026-05-03T00:00:00Z', updated_at: '2026-05-18T00:00:00Z' },
    { number: 4301, closed_at: '2026-05-08T00:00:00Z', updated_at: '2026-05-17T00:00:00Z' },
    { number: 4300, closed_at: '2026-05-04T00:00:00Z', updated_at: '2026-05-16T00:00:00Z' },
    { number: 4299, closed_at: '2026-05-07T00:00:00Z', updated_at: '2026-05-15T00:00:00Z' },
    { number: 4283, closed_at: '2026-05-09T00:00:00Z', updated_at: '2026-05-14T00:00:00Z' },
    { number: 4210, closed_at: '2026-05-10T00:00:00Z', updated_at: '2026-05-13T00:00:00Z' },
    { number: 4200, closed_at: '2026-04-01T00:00:00Z', updated_at: '2026-04-01T00:00:00Z' },
  ];

  fs.writeFileSync(fakeGhPath, `#!/usr/bin/env node
const closedIssues = ${JSON.stringify(fakeClosedIssues)};
const args = process.argv.slice(2);
if (args[0] === 'api') {
  const url = args[1] || '';
  const page = Number(new URL('https://example.invalid/' + url).searchParams.get('page') || '1');
  process.stdout.write(JSON.stringify(page === 1 ? closedIssues : []));
  process.exit(0);
}
console.error('unexpected gh invocation: ' + args.join(' '));
process.exit(1);
`, { mode: 0o755 });

  const originalPath = process.env.PATH ?? '';
  const selectedIssues = [];
  process.env.PATH = `${tempDir}${path.delimiter}${originalPath}`;
  try {
    const result = verifierModule.verifyIssueLifecycleEvidence({
      argv: ['--recent-closed', '3'],
      readIssuePayload: (issue) => {
        selectedIssues.push(String(issue));
        return {
          number: Number(issue),
          state: 'CLOSED',
          comments: [{ body: validCloseoutComment() }],
        };
      },
      evidenceContext: {
        repoSlug: 'example/repo',
        verifyCommit: () => {},
      },
    });

    assert.equal(result.mode, 'recent-closed');
    assert.deepEqual(
      selectedIssues,
      ['4210', '4283', '4301'],
      'recent-closed should sort the fetched closed issue window by closedAt before applying the requested limit',
    );
  } finally {
    process.env.PATH = originalPath;
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
});

test('manual gate evidence targets are explicit instead of historical issue defaults', async () => {
  const { TEMPLATE_SPECS } = await import('../../../manual-gate/templates.mjs');
  const generatorPath = path.join(repoRoot, 'scripts', 'manual-gate', 'generate_report.mjs');
  const missingTarget = spawnSync(process.execPath, [
    generatorPath,
    '--template',
    'mcp-e2e',
    '--date',
    '2026-03-04',
    '--out',
    'package.json',
  ], {
    cwd: repoRoot,
    encoding: 'utf8',
  });

  assert.notEqual(missingTarget.status, 0, 'manual gate report generation should reject missing evidence targets');
  assert.match(
    `${missingTarget.stdout}\n${missingTarget.stderr}`,
    /--issue|--pr|--release-target|evidence target/i,
    'missing-target failure should explain that an explicit evidence target is required',
  );

  const serializedSpecs = JSON.stringify(TEMPLATE_SPECS);
  assert.equal(
    Object.values(TEMPLATE_SPECS).some((spec) => Object.hasOwn(spec, 'defaultIssue')),
    false,
    'manual gate template specs should not carry historical default issue targets',
  );
  assert.doesNotMatch(serializedSpecs, /\b(?:168|169|170)\b/, 'manual gate specs should not hard-code closed historical issue numbers');

  for (const relativePath of [
    'docs/execution/MCP_E2E_VALIDATION.md',
    'docs/execution/MENUBAR_REGRESSION_CHECKLIST.md',
    'docs/execution/SETTINGS_REGRESSION_CHECKLIST.md',
    'docs/execution/SYNC_RECOVERY_PLAYBOOK.md',
  ]) {
    const content = fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
    assert.doesNotMatch(
      content,
      /(?:--issue\s+(?:168|169|170)\b|issue-(?:168|169|170)\.md|issue\s+#(?:168|169|170)\b|\(#(?:168|169|170)\))/i,
      `${relativePath} should not route new manual-gate evidence to historical closed issues`,
    );
    assert.match(
      content,
      /--issue <current-issue>|--pr <current-pr>|--release-target <release-target>/,
      `${relativePath} should document an explicit current evidence target`,
    );
  }
});
