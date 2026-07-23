#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

import {
  assertContract,
  resolveRepoRootFromMeta,
  runVerifierCli,
} from '../lib/verifier_runtime.mjs';

const SCRIPT_TAG = '[open_issue_lifecycle]';
const DEFAULT_OPEN_LIMIT = 200;
const PRIORITY_LABELS = new Set(['priority-p0', 'priority-p1', 'priority-p2']);
const TYPE_LABELS = new Set(['type-task', 'type-quality', 'type-epic', 'maintenance']);
const READINESS_LABELS = new Set(['needs-design', 'agent-ready']);
const TRACKER_EXEMPT_LABELS = new Set(['discussion']);
const INHERENT_READINESS_EXEMPT_LABELS = new Set(['type-epic', 'discussion', 'blocked', 'blocked-external']);
const EXCEPTION_FILE = path.join('scripts', 'verify', 'open_issue_lifecycle_exceptions.json');

function labelNames(issue) {
  return new Set(
    (Array.isArray(issue?.labels) ? issue.labels : [])
      .map((label) => typeof label === 'string' ? label : label?.name)
      .filter((name) => typeof name === 'string' && name.trim().length > 0)
      .map((name) => name.trim()),
  );
}

function issueRef(issue) {
  return `#${issue?.number ?? 'unknown'} ${issue?.title ?? '(untitled)'}`;
}

function staleExceptionFix(number) {
  return `Fix: remove #${number} from ${EXCEPTION_FILE}, or relabel the issue so the exception only waives a tracker issue's missing readiness label.`;
}

function isExplicitlyNonOpen(issue) {
  if (typeof issue?.state !== 'string') return false;
  return issue.state.trim().toUpperCase() !== 'OPEN';
}

function normalizeExceptionEntries(value) {
  if (!Array.isArray(value)) return new Map();
  return new Map(value.map((entry) => {
    const number = Number(entry?.number);
    const reason = typeof entry?.reason === 'string' ? entry.reason.trim() : '';
    assertContract(Number.isInteger(number) && number > 0, SCRIPT_TAG, 'open issue lifecycle exception numbers must be positive integers');
    assertContract(reason.length >= 12, SCRIPT_TAG, `open issue lifecycle exception #${number} must include a concrete reason`);
    return [number, reason];
  }));
}

function loadReadinessExceptions(repoRoot) {
  const exceptionPath = path.join(repoRoot, EXCEPTION_FILE);
  if (!fs.existsSync(exceptionPath)) {
    return new Map();
  }
  const parsed = JSON.parse(fs.readFileSync(exceptionPath, 'utf8'));
  return normalizeExceptionEntries(parsed.missingReadinessIssueNumbers);
}

function isReadinessExempt(issue, labels, readinessExceptions) {
  if (Array.from(INHERENT_READINESS_EXEMPT_LABELS).some((label) => labels.has(label))) {
    return true;
  }
  return readinessExceptions.has(Number(issue?.number));
}

function collectIssueFindings(issue, { readinessExceptions = new Map() } = {}) {
  const labels = labelNames(issue);
  if (isExplicitlyNonOpen(issue)) {
    return [];
  }
  if (!labels.has('tracker') && Array.from(TRACKER_EXEMPT_LABELS).some((label) => labels.has(label))) {
    return [];
  }
  if (!labels.has('tracker')) {
    return [`${issueRef(issue)} must have a tracker label or documented non-executable exemption label`];
  }

  const findings = [];
  const priorityCount = Array.from(PRIORITY_LABELS).filter((label) => labels.has(label)).length;
  const typeCount = Array.from(TYPE_LABELS).filter((label) => labels.has(label)).length;
  const readinessCount = Array.from(READINESS_LABELS).filter((label) => labels.has(label)).length;

  if (priorityCount !== 1) {
    findings.push(`${issueRef(issue)} must have exactly one priority label`);
  }
  if (typeCount < 1) {
    findings.push(`${issueRef(issue)} must have at least one type lane label`);
  }
  if (!isReadinessExempt(issue, labels, readinessExceptions) && readinessCount !== 1) {
    findings.push(`${issueRef(issue)} must have exactly one readiness label (needs-design or agent-ready)`);
  }

  return findings;
}

function collectReadinessExceptionFindings(issues, readinessExceptions) {
  const issueByNumber = new Map(issues.map((issue) => [Number(issue?.number), issue]));
  const findings = [];

  for (const number of readinessExceptions.keys()) {
    const issue = issueByNumber.get(number);
    if (!issue) {
      findings.push(`#${number} has a stale readiness exception because the matching issue is not open in the payload. ${staleExceptionFix(number)}`);
      continue;
    }

    if (isExplicitlyNonOpen(issue)) {
      findings.push(`${issueRef(issue)} has a stale readiness exception #${number} because its state is ${issue.state}, not OPEN. ${staleExceptionFix(number)}`);
      continue;
    }

    const labels = labelNames(issue);
    if (!labels.has('tracker')) {
      findings.push(`${issueRef(issue)} has a stale readiness exception #${number} because it is not a tracker issue. ${staleExceptionFix(number)}`);
      continue;
    }
    const readinessCount = Array.from(READINESS_LABELS).filter((label) => labels.has(label)).length;
    if (readinessCount > 0) {
      findings.push(`${issueRef(issue)} has a stale readiness exception #${number} because it already has a readiness label. ${staleExceptionFix(number)}`);
      continue;
    }

    const inherentReadinessExemptLabels = Array.from(INHERENT_READINESS_EXEMPT_LABELS).filter((label) => labels.has(label));
    if (inherentReadinessExemptLabels.length > 0) {
      findings.push(`${issueRef(issue)} has a stale readiness exception #${number} because ${inherentReadinessExemptLabels.join(', ')} already exempts it from readiness. ${staleExceptionFix(number)}`);
      continue;
    }

    const priorityCount = Array.from(PRIORITY_LABELS).filter((label) => labels.has(label)).length;
    const typeCount = Array.from(TYPE_LABELS).filter((label) => labels.has(label)).length;
    if (priorityCount !== 1 || typeCount < 1) {
      findings.push(`${issueRef(issue)} has a stale readiness exception #${number} because it no longer maps exactly to the missing-readiness condition. ${staleExceptionFix(number)}`);
    }
  }

  return findings;
}

export function verifyOpenIssueLifecyclePayload(issues, {
  readinessExceptions = new Map(),
} = {}) {
  assertContract(Array.isArray(issues), SCRIPT_TAG, 'open issue payload must be an array');

  const findings = [
    ...collectReadinessExceptionFindings(issues, readinessExceptions),
    ...issues.flatMap((issue) => collectIssueFindings(issue, { readinessExceptions })),
  ];
  assertContract(
    findings.length === 0,
    SCRIPT_TAG,
    `Open issue lifecycle checks failed:\n- ${findings.join('\n- ')}`,
  );

  return { ok: true, checkedIssues: issues.length };
}

function readOpenIssuesWithGh({ limit = DEFAULT_OPEN_LIMIT } = {}) {
  let raw;
  try {
    raw = execFileSync('gh', [
      'issue',
      'list',
      '--state',
      'open',
      '--limit',
      String(limit),
      '--json',
      'number,title,labels,url',
    ], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (error) {
    const stderr = error?.stderr ? String(error.stderr).trim() : '';
    throw new Error(`${SCRIPT_TAG} failed to read open issues with gh${stderr ? `: ${stderr}` : ''}`);
  }
  return JSON.parse(raw);
}

function parseArgs(argv) {
  const options = {
    fixture: null,
    limit: DEFAULT_OPEN_LIMIT,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === '--fixture') {
      const value = argv[index + 1];
      assertContract(value && !value.startsWith('--'), SCRIPT_TAG, 'Missing value for --fixture');
      options.fixture = value;
      index += 1;
      continue;
    }
    if (token === '--limit') {
      const value = argv[index + 1];
      assertContract(value && /^\d+$/.test(value), SCRIPT_TAG, 'Missing or invalid value for --limit');
      options.limit = Number(value);
      assertContract(options.limit > 0 && options.limit <= 500, SCRIPT_TAG, '--limit must be between 1 and 500');
      index += 1;
      continue;
    }
    throw new Error(`${SCRIPT_TAG} Unknown argument: ${token}`);
  }

  return options;
}

export function verifyOpenIssueLifecycle({
  argv = [],
  repoRoot = resolveRepoRootFromMeta(import.meta.url),
  readOpenIssues = readOpenIssuesWithGh,
} = {}) {
  const options = parseArgs(argv);
  const readinessExceptions = loadReadinessExceptions(repoRoot);
  const issues = options.fixture
    ? JSON.parse(fs.readFileSync(path.resolve(repoRoot, options.fixture), 'utf8'))
    : readOpenIssues({ limit: options.limit });

  return verifyOpenIssueLifecyclePayload(issues, { readinessExceptions });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  runVerifierCli({
    scriptTag: SCRIPT_TAG,
    run: () => {
      const result = verifyOpenIssueLifecycle({ argv: process.argv.slice(2) });
      console.log(`${SCRIPT_TAG} OK: checked ${result.checkedIssues} open issue(s).`);
    },
  });
}
