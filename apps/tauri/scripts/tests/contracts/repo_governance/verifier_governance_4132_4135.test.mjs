import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from '../shared.mjs';
import { displayCommand, flattenBundle } from '../../../verify/verification_manifest.mjs';

const MANUAL_GATE_DATE = '2099-01-01';
const MANUAL_GATE_TARGET = 'contract-4134';
const MANUAL_GATE_TEMPLATES = ['mcp-e2e', 'ui-regression', 'sync-recovery'];
const MANUAL_GATE_OUTPUT_DIR_ENV = 'LORVEX_MANUAL_GATE_OUTPUT_DIR';

function runNode(args, options = {}) {
  return spawnSync(process.execPath, args, {
    cwd: repoRoot,
    encoding: 'utf8',
    ...options,
  });
}

function runNodeAsync(args, options = {}) {
  return new Promise((resolve) => {
    const child = spawn(process.execPath, args, {
      cwd: repoRoot,
      ...options,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stderr = '';
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', (chunk) => {
      stdout += chunk;
    });
    child.stderr.on('data', (chunk) => {
      stderr += chunk;
    });
    child.on('close', (status, signal) => {
      resolve({ status, signal, stdout, stderr });
    });
  });
}

function assertLifecycleFailure(callback, patterns) {
  let error;
  try {
    callback();
  } catch (caught) {
    error = caught;
  }
  assert.ok(error, 'expected open issue lifecycle verifier to fail');
  for (const pattern of patterns) {
    assert.match(error.message, pattern);
  }
}

function writeManualGateFixtureReports({ repoSlug = 'boyugou/lorvex', offRepo = false } = {}) {
  const outputRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'lorvex-manual-gate-fixtures-'));
  const env = {
    ...process.env,
    [MANUAL_GATE_OUTPUT_DIR_ENV]: outputRoot,
  };

  for (const template of MANUAL_GATE_TEMPLATES) {
    const generated = runNode([
      'scripts/manual-gate/generate_report.mjs',
      '--template',
      template,
      '--date',
      MANUAL_GATE_DATE,
      '--release-target',
      MANUAL_GATE_TARGET,
      '--commit',
      '5ef3c8f',
    ], { env });
    assert.equal(generated.status, 0, generated.stderr);
    assert.doesNotMatch(generated.stdout, /\.\.\//);
  }

  const replacements = [
    ['mcp-e2e', `https://github.com/${offRepo ? 'example/repo' : repoSlug}/issues/4134#issuecomment-1001`],
    ['ui-regression', `https://github.com/${repoSlug}/pull/9#discussion_r1002`],
    ['sync-recovery', `https://github.com/${repoSlug}/issues/4134#issuecomment-1003`],
  ];

  for (const [slug, permalink] of replacements) {
    const reportPath = path.join(
      outputRoot,
      slug,
      MANUAL_GATE_DATE,
      `release-${MANUAL_GATE_TARGET}.md`,
    );
    let content = fs.readFileSync(reportPath, 'utf8');
    content = content
      .replace(/- Operator: .*/, '- Operator: contract verifier')
      .replace(/- Runtime: .*/, '- Runtime: node contract fixture')
      .replace(/- App\/MCP build notes: .*/, '- App/MCP build notes: local fixture')
      .replace(/- Evidence bundle: .*/, '- Evidence bundle: artifacts/manual-gates')
      .replace(/- Evidence permalink: .*/, `- Evidence permalink: ${permalink}`)
      .replace(/- Evidence owner: .*/, '- Evidence owner: contract verifier')
      .replace(/- Status: .*/, '- Status: PASS')
      .replace(/- Blocking defects: .*/, '- Blocking defects: none')
      .replace(/- Summary: .*/, '- Summary: Contract fixture.');
    fs.writeFileSync(reportPath, content, 'utf8');
  }

  return { outputRoot, env };
}

function rewriteManualGateFixtureField(outputRoot, slug, fieldLabel, value) {
  const reportPath = path.join(
    outputRoot,
    slug,
    MANUAL_GATE_DATE,
    `release-${MANUAL_GATE_TARGET}.md`,
  );
  const content = fs.readFileSync(reportPath, 'utf8');
  const escaped = fieldLabel.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const next = content.replace(new RegExp(`^- ${escaped}: .*$`, 'm'), `- ${fieldLabel}: ${value}`);
  assert.notEqual(next, content, `expected fixture field ${fieldLabel} to be present`);
  fs.writeFileSync(reportPath, next, 'utf8');
}

test('open issue lifecycle verifier validates fixture label hygiene', async () => {
  const verifier = await import('../../../verify/open_issue_lifecycle.mjs');
  const validIssue = {
    number: 1,
    title: 'Valid executable issue',
    labels: [
      { name: 'tracker' },
      { name: 'priority-p1' },
      { name: 'type-task' },
      { name: 'agent-ready' },
    ],
  };

  assert.equal(typeof verifier.verifyOpenIssueLifecyclePayload, 'function');
  assert.doesNotThrow(() => verifier.verifyOpenIssueLifecyclePayload([validIssue]));
  assert.throws(
    () => verifier.verifyOpenIssueLifecyclePayload([{ ...validIssue, labels: validIssue.labels.filter((label) => label.name !== 'priority-p1') }]),
    /exactly one priority/i,
  );
  assert.throws(
    () => verifier.verifyOpenIssueLifecyclePayload([{ ...validIssue, labels: [...validIssue.labels, { name: 'priority-p2' }] }]),
    /exactly one priority/i,
  );
  assert.throws(
    () => verifier.verifyOpenIssueLifecyclePayload([{ ...validIssue, labels: validIssue.labels.filter((label) => label.name !== 'type-task') }]),
    /type lane/i,
  );
  assert.throws(
    () => verifier.verifyOpenIssueLifecyclePayload([{ ...validIssue, labels: validIssue.labels.filter((label) => label.name !== 'agent-ready') }]),
    /readiness/i,
  );
  assertLifecycleFailure(
    () => verifier.verifyOpenIssueLifecyclePayload([
      {
        number: 5,
        title: 'Unlabeled executable issue',
        labels: [],
      },
    ]),
    [/#5/, /tracker label/i],
  );

  const legacyReadinessExceptionIssue = {
    number: 2,
    title: 'Legacy issue missing readiness',
    labels: [
      { name: 'tracker' },
      { name: 'priority-p2' },
      { name: 'type-task' },
    ],
  };
  assert.doesNotThrow(() => verifier.verifyOpenIssueLifecyclePayload(
    [legacyReadinessExceptionIssue],
    { readinessExceptions: new Map([[2, 'legacy issue predating readiness hygiene']]) },
  ));
  assertLifecycleFailure(
    () => verifier.verifyOpenIssueLifecyclePayload(
      [legacyReadinessExceptionIssue],
      { readinessExceptions: new Map([[404, 'closed issue left in exceptions']]) },
    ),
    [/#404/, /remove.*open_issue_lifecycle_exceptions\.json/i],
  );
  assertLifecycleFailure(
    () => verifier.verifyOpenIssueLifecyclePayload(
      [validIssue],
      { readinessExceptions: new Map([[1, 'issue already received readiness label']]) },
    ),
    [/#1/, /remove.*open_issue_lifecycle_exceptions\.json/i],
  );
  assertLifecycleFailure(
    () => verifier.verifyOpenIssueLifecyclePayload(
      [{ ...legacyReadinessExceptionIssue, labels: legacyReadinessExceptionIssue.labels.filter((label) => label.name !== 'tracker') }],
      { readinessExceptions: new Map([[2, 'non-tracker issue left in exceptions']]) },
    ),
    [/#2/, /remove.*open_issue_lifecycle_exceptions\.json/i],
  );
});

test('open issue lifecycle verifier rejects stale readiness exceptions that no longer map to missing readiness', async () => {
  const verifier = await import('../../../verify/open_issue_lifecycle.mjs');
  const inherentlyReadinessExemptIssue = {
    number: 3,
    title: 'Blocked issue no longer needing readiness',
    labels: [
      { name: 'tracker' },
      { name: 'priority-p2' },
      { name: 'type-task' },
      { name: 'blocked' },
    ],
  };

  assertLifecycleFailure(
    () => verifier.verifyOpenIssueLifecyclePayload(
      [inherentlyReadinessExemptIssue],
      { readinessExceptions: new Map([[3, 'legacy blocked issue predating readiness hygiene']]) },
    ),
    [/#3/, /remove.*open_issue_lifecycle_exceptions\.json/i],
  );
});

test('open issue lifecycle verifier treats external blockers as inherently not agent-ready', async () => {
  const verifier = await import('../../../verify/open_issue_lifecycle.mjs');
  const issueLifecycle = fs.readFileSync(path.join(repoRoot, 'docs', 'execution', 'ISSUE_LIFECYCLE.md'), 'utf8');
  const externalBlockedIssue = {
    number: 4096,
    title: 'Provision external mail routing',
    labels: [
      { name: 'tracker' },
      { name: 'priority-p2' },
      { name: 'maintenance' },
      { name: 'blocked-external' },
    ],
  };

  assert.doesNotThrow(() => verifier.verifyOpenIssueLifecyclePayload([externalBlockedIssue]));
  assertLifecycleFailure(
    () => verifier.verifyOpenIssueLifecyclePayload(
      [externalBlockedIssue],
      { readinessExceptions: new Map([[4096, 'external blocker should not also need a readiness waiver']]) },
    ),
    [/#4096/, /remove.*open_issue_lifecycle_exceptions\.json/i],
  );
  assert.match(issueLifecycle, /blocked-external/, 'issue lifecycle docs should explain external blockers');
});

test('open issue lifecycle verifier rejects readiness exceptions for non-open fixture issues', async () => {
  const verifier = await import('../../../verify/open_issue_lifecycle.mjs');
  const closedIssue = {
    number: 4,
    title: 'Closed issue left in exception fixture',
    state: 'CLOSED',
    labels: [
      { name: 'tracker' },
      { name: 'priority-p2' },
      { name: 'type-task' },
    ],
  };

  assertLifecycleFailure(
    () => verifier.verifyOpenIssueLifecyclePayload(
      [closedIssue],
      { readinessExceptions: new Map([[4, 'legacy closed issue predating readiness hygiene']]) },
    ),
    [/#4/, /remove.*open_issue_lifecycle_exceptions\.json/i],
  );
});

test('open issue lifecycle verifier is exposed through package scripts and repo governance', () => {
  const packageJson = JSON.parse(fs.readFileSync(path.join(repoRoot, 'package.json'), 'utf8'));
  const issueLifecycle = fs.readFileSync(path.join(repoRoot, 'docs', 'execution', 'ISSUE_LIFECYCLE.md'), 'utf8');
  const repoGovernanceCommands = flattenBundle('verify:repo-governance').map(displayCommand);

  assert.equal(packageJson.scripts['verify:open-issue-lifecycle'], 'node scripts/verify/open_issue_lifecycle.mjs');
  assert.equal(repoGovernanceCommands.includes('npm run verify:open-issue-lifecycle'), true);
  assert.match(issueLifecycle, /npm run verify:open-issue-lifecycle/);
});

test('issue lifecycle type-lane wording matches the open issue verifier semantics', async () => {
  const verifier = await import('../../../verify/open_issue_lifecycle.mjs');
  const issueLifecycle = fs.readFileSync(path.join(repoRoot, 'docs', 'execution', 'ISSUE_LIFECYCLE.md'), 'utf8');
  const multiTypeIssue = {
    number: 4312,
    title: 'Issue with useful secondary type lane labels',
    labels: [
      { name: 'tracker' },
      { name: 'priority-p2' },
      { name: 'type-task' },
      { name: 'maintenance' },
      { name: 'agent-ready' },
    ],
  };

  assert.match(issueLifecycle, /at least one type lane label/i);
  assert.doesNotMatch(issueLifecycle, /\bone type label\b/i);
  assert.match(issueLifecycle, /maintenance.*type lane/i);
  assert.doesNotThrow(() => verifier.verifyOpenIssueLifecyclePayload([multiTypeIssue]));
});

test('manual gate evidence rejects off-repository permalinks and keeps same-repository issue and PR permalinks valid', () => {
  const { outputRoot, env } = writeManualGateFixtureReports();
  try {
    assert.notEqual(path.resolve(outputRoot), path.join(repoRoot, 'artifacts', 'manual-gates'));

    const sameRepo = runNode(['scripts/verify/manual_gate_evidence.mjs'], { env });
    assert.equal(sameRepo.status, 0, sameRepo.stderr);
    assert.doesNotMatch(`${sameRepo.stdout}\n${sameRepo.stderr}`, /\.\.\//);

    const duplicateReport = runNode([
      'scripts/manual-gate/generate_report.mjs',
      '--template',
      'mcp-e2e',
      '--date',
      MANUAL_GATE_DATE,
      '--release-target',
      MANUAL_GATE_TARGET,
      '--commit',
      '5ef3c8f',
    ], { env });
    assert.notEqual(duplicateReport.status, 0);
    assert.match(duplicateReport.stderr, /Output already exists:/);
    assert.doesNotMatch(`${duplicateReport.stdout}\n${duplicateReport.stderr}`, /\.\.\//);

    const offRepoFixture = writeManualGateFixtureReports({ offRepo: true });
    try {
      const offRepo = runNode(['scripts/verify/manual_gate_evidence.mjs'], { env: offRepoFixture.env });
      assert.notEqual(offRepo.status, 0);
      assert.match(offRepo.stderr, /must belong to this repository/i);
      assert.match(offRepo.stderr, /example\/repo/i);
    } finally {
      fs.rmSync(offRepoFixture.outputRoot, { recursive: true, force: true });
    }
  } finally {
    fs.rmSync(outputRoot, { recursive: true, force: true });
  }
});

test('manual gate release enforcement requires PASS status and no blocking defects', () => {
  const validFixture = writeManualGateFixtureReports();
  try {
    const releasePass = runNode(['scripts/verify/manual_gate_evidence.mjs', '--enforce-release'], { env: validFixture.env });
    assert.equal(releasePass.status, 0, releasePass.stderr);
  } finally {
    fs.rmSync(validFixture.outputRoot, { recursive: true, force: true });
  }

  const cases = [
    {
      name: 'partial status',
      fieldLabel: 'Status',
      value: 'PARTIAL',
      expected: /release enforcement requires Status: PASS/i,
    },
    {
      name: 'fail status',
      fieldLabel: 'Status',
      value: 'FAIL',
      expected: /release enforcement requires Status: PASS/i,
    },
    {
      name: 'blocking defects',
      fieldLabel: 'Blocking defects',
      value: 'https://github.com/boyugou/lorvex/issues/4302',
      expected: /release enforcement requires Blocking defects: none/i,
    },
  ];

  for (const testCase of cases) {
    const fixture = writeManualGateFixtureReports();
    try {
      rewriteManualGateFixtureField(fixture.outputRoot, 'mcp-e2e', testCase.fieldLabel, testCase.value);
      const result = runNode(['scripts/verify/manual_gate_evidence.mjs', '--enforce-release'], { env: fixture.env });
      assert.notEqual(result.status, 0, `${testCase.name} should fail release enforcement`);
      assert.match(result.stderr, testCase.expected);
    } finally {
      fs.rmSync(fixture.outputRoot, { recursive: true, force: true });
    }
  }
});

test('manual gate smoke metadata uses neutral gate IDs and has a blocking repo-governance verifier', () => {
  const packageJson = JSON.parse(fs.readFileSync(path.join(repoRoot, 'package.json'), 'utf8'));
  const smokeSource = fs.readFileSync(path.join(repoRoot, 'scripts', 'manual-gate', 'smoke_runner.mjs'), 'utf8');
  const repoGovernanceCommands = flattenBundle('verify:repo-governance').map(displayCommand);

  assert.equal(packageJson.scripts['verify:manual-gate-smoke-metadata'], 'node scripts/verify/manual_gate_smoke_metadata.mjs');
  assert.equal(repoGovernanceCommands.includes('npm run verify:manual-gate-smoke-metadata'), true);
  assert.doesNotMatch(smokeSource, /\b(?:168|169|170|208)\b/);
});

test('manual gate smoke metadata verifier isolates concurrent scratch output', async () => {
  const fixedScratchDir = path.join(repoRoot, 'artifacts', 'manual-gate-smoke-metadata');
  const sentinelPath = path.join(fixedScratchDir, 'sentinel.txt');
  fs.rmSync(fixedScratchDir, { recursive: true, force: true });
  fs.mkdirSync(fixedScratchDir, { recursive: true });
  fs.writeFileSync(sentinelPath, 'must survive verifier scratch cleanup\n', 'utf8');

  try {
    const [first, second] = await Promise.all([
      runNodeAsync(['scripts/verify/manual_gate_smoke_metadata.mjs']),
      runNodeAsync(['scripts/verify/manual_gate_smoke_metadata.mjs']),
    ]);

    for (const [index, result] of [first, second].entries()) {
      assert.equal(result.status, 0, `run ${index + 1} failed\nstdout:\n${result.stdout}\nstderr:\n${result.stderr}`);
    }
    assert.equal(fs.readFileSync(sentinelPath, 'utf8'), 'must survive verifier scratch cleanup\n');
  } finally {
    fs.rmSync(fixedScratchDir, { recursive: true, force: true });
  }
});
