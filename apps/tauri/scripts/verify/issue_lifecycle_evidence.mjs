#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  assertContract,
  resolveRepoRootFromMeta,
  runVerifierCli,
} from '../lib/verifier_runtime.mjs';

const SCRIPT_TAG = '[issue_lifecycle_evidence]';
const DEFAULT_RECENT_CLOSED_LIMIT = 5;
const MAX_RECENT_CLOSED_LIMIT = 50;
const RECENT_CLOSED_PAGE_SIZE = 100;

export const GITHUB_ISSUE_OR_PR_PERMALINK_RE =
  /^https:\/\/github\.com\/([^/\s]+)\/([^/\s]+)\/(?:issues|pull)\/\d+#(?:issuecomment-\d+|discussion_r\d+)$/;

const COMMIT_RE = /^[0-9a-f]{7,40}$/i;
const ORIGIN_MAIN_REF = 'origin/main';
const REQUIRED_SECTIONS = [
  {
    key: 'outcome',
    names: ['Outcome'],
  },
  {
    key: 'whatChanged',
    names: ['What changed'],
  },
  {
    key: 'verification',
    names: ['Verification'],
  },
  {
    key: 'risk',
    names: ['Risk', 'Risk-Follow-up', 'Risk / follow-up', 'Risk and follow-up', 'Risk or follow-up issue'],
  },
];

function normalizeHeading(line) {
  return line
    .trim()
    .replace(/^#{1,6}\s+/, '')
    .replace(/^\*\*/, '')
    .replace(/\*\*:?$/, '')
    .replace(/:$/, '')
    .trim()
    .toLowerCase();
}

function sectionMap(content) {
  const sections = new Map();
  let currentKey = null;

  for (const rawLine of content.split(/\r?\n/)) {
    const normalized = normalizeHeading(rawLine);
    const section = REQUIRED_SECTIONS.find((candidate) => (
      candidate.names.some((name) => normalized === name.toLowerCase())
    ));

    if (section) {
      currentKey = section.key;
      sections.set(currentKey, []);
      continue;
    }

    if (/^#{1,6}\s+/.test(rawLine.trim()) || /^\*\*[^*]+\*\*:?\s*$/.test(rawLine.trim())) {
      currentKey = null;
      continue;
    }

    if (currentKey) {
      sections.get(currentKey).push(rawLine);
    }
  }

  return sections;
}

function fieldValue(content, fieldLabel) {
  const escaped = fieldLabel.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = content.match(new RegExp(`^(?:[-*]\\s*)?${escaped}:\\s*(.+)$`, 'im'));
  return match?.[1]?.trim() ?? null;
}

function isPlaceholder(value) {
  if (!value) return true;
  if (value.includes('{{') || value.includes('}}')) return true;
  if (/^<[^>]+>$/.test(value)) return true;
  if (value.includes('<') && value.includes('>')) return true;
  return false;
}

function requireField(content, label) {
  const value = fieldValue(content, label);
  assertContract(value, SCRIPT_TAG, `close-out comment missing required field: ${label}`);
  assertContract(!isPlaceholder(value), SCRIPT_TAG, `close-out field still contains placeholder text: ${label}`);
  return value;
}

function normalizeRepoSlug(value) {
  return value?.trim().toLowerCase() ?? '';
}

export function parseGitHubRepoSlugFromRemoteUrl(remoteUrl) {
  const trimmed = remoteUrl?.trim();
  if (!trimmed) return null;

  const normalized = trimmed.replace(/\.git$/i, '');
  const patterns = [
    /^https?:\/\/github\.com\/([^/\s]+)\/([^/\s]+)$/i,
    /^git@github\.com:([^/\s]+)\/([^/\s]+)$/i,
    /^ssh:\/\/git@github\.com\/([^/\s]+)\/([^/\s]+)$/i,
  ];

  for (const pattern of patterns) {
    const match = normalized.match(pattern);
    if (match) {
      return normalizeRepoSlug(`${match[1]}/${match[2]}`);
    }
  }

  return null;
}

function runGit(repoRoot, args, failureMessage) {
  try {
    return execFileSync('git', ['-C', repoRoot, ...args], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    }).trim();
  } catch (error) {
    const stderr = error?.stderr ? String(error.stderr).trim() : '';
    throw new Error(`${SCRIPT_TAG} ${failureMessage}${stderr ? `: ${stderr}` : ''}`);
  }
}

function tryRunGit(repoRoot, args) {
  try {
    return execFileSync('git', ['-C', repoRoot, ...args], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
  } catch {
    return null;
  }
}

export function resolveGitHubRepoSlug({ repoRoot = resolveRepoRootFromMeta(import.meta.url) } = {}) {
  const originUrl = tryRunGit(repoRoot, ['config', '--get', 'remote.origin.url']);
  const originSlug = parseGitHubRepoSlugFromRemoteUrl(originUrl);
  if (originSlug) return originSlug;

  try {
    const ghSlug = execFileSync('gh', ['repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner'], {
      cwd: repoRoot,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    }).trim();
    if (ghSlug) return normalizeRepoSlug(ghSlug);
  } catch (error) {
    const stderr = error?.stderr ? String(error.stderr).trim() : '';
    throw new Error(`${SCRIPT_TAG} failed to resolve GitHub repository slug from origin or gh${stderr ? `: ${stderr}` : ''}`);
  }

  throw new Error(`${SCRIPT_TAG} failed to resolve GitHub repository slug from origin or gh`);
}

function repoSlugFromEvidencePermalink(evidencePermalink) {
  const match = evidencePermalink.match(GITHUB_ISSUE_OR_PR_PERMALINK_RE);
  return match ? normalizeRepoSlug(`${match[1]}/${match[2]}`) : null;
}

function assertEvidencePermalinkBelongsToRepo(evidencePermalink, repoSlug) {
  const permalinkRepoSlug = repoSlugFromEvidencePermalink(evidencePermalink);
  assertContract(
    permalinkRepoSlug === normalizeRepoSlug(repoSlug),
    SCRIPT_TAG,
    `Evidence permalink must belong to this repository (${repoSlug}), got ${evidencePermalink}`,
  );
}

function refreshOriginMain({ repoRoot }) {
  runGit(repoRoot, ['fetch', '--quiet', 'origin', 'main'], 'failed to refresh origin/main before validating close-out commit reachability');
}

export function resolveOriginMainCommit({ repoRoot = resolveRepoRootFromMeta(import.meta.url) } = {}) {
  return runGit(repoRoot, ['rev-parse', '--verify', ORIGIN_MAIN_REF], `failed to resolve ${ORIGIN_MAIN_REF}`);
}

export function verifyCommitReachableFromOriginMain({
  commit,
  repoRoot = resolveRepoRootFromMeta(import.meta.url),
} = {}) {
  assertContract(COMMIT_RE.test(commit), SCRIPT_TAG, `Commit must be a 7-40 character git SHA, got ${commit}`);
  runGit(repoRoot, ['cat-file', '-e', `${commit}^{commit}`], `Commit must resolve to a local git commit, got ${commit}`);
  runGit(
    repoRoot,
    ['merge-base', '--is-ancestor', commit, ORIGIN_MAIN_REF],
    `Commit must be reachable from ${ORIGIN_MAIN_REF}, got ${commit}`,
  );
}

function createEvidenceContext({
  repoRoot = resolveRepoRootFromMeta(import.meta.url),
  repoSlug = null,
  verifyCommit = null,
  refreshMain = false,
} = {}) {
  if (refreshMain) {
    refreshOriginMain({ repoRoot });
  }

  return {
    repoRoot,
    repoSlug: normalizeRepoSlug(repoSlug ?? resolveGitHubRepoSlug({ repoRoot })),
    verifyCommit: verifyCommit ?? ((commit) => verifyCommitReachableFromOriginMain({ repoRoot, commit })),
  };
}

function assertNonEmptySection(sections, section) {
  const body = sections.get(section.key)?.join('\n').trim() ?? '';
  assertContract(
    body.length > 0,
    SCRIPT_TAG,
    `close-out comment missing non-empty ${section.names.join(' / ')} section`,
  );
}

export function verifyCloseoutComment(content, {
  source = 'close-out comment',
  repoRoot = resolveRepoRootFromMeta(import.meta.url),
  evidenceContext = null,
  repoSlug = null,
  verifyCommit = null,
} = {}) {
  assertContract(typeof content === 'string' && content.trim().length > 0, SCRIPT_TAG, `${source} is empty`);

  const sections = sectionMap(content);
  for (const section of REQUIRED_SECTIONS) {
    assertNonEmptySection(sections, section);
  }

  const evidencePermalink = requireField(content, 'Evidence permalink');
  assertContract(
    GITHUB_ISSUE_OR_PR_PERMALINK_RE.test(evidencePermalink),
    SCRIPT_TAG,
    `Evidence permalink must be a GitHub issue/PR comment permalink, got ${evidencePermalink}`,
  );

  const commit = requireField(content, 'Commit');
  assertContract(
    COMMIT_RE.test(commit),
    SCRIPT_TAG,
    `Commit must be a 7-40 character git SHA, got ${commit}`,
  );

  const context = evidenceContext ?? createEvidenceContext({ repoRoot, repoSlug, verifyCommit });
  assertEvidencePermalinkBelongsToRepo(evidencePermalink, context.repoSlug);
  context.verifyCommit(commit);

  return {
    ok: true,
    evidencePermalink,
    commit,
  };
}

export function verifyIssuePayload(payload, { evidenceContext = null } = {}) {
  assertContract(payload && typeof payload === 'object', SCRIPT_TAG, 'issue payload must be an object');
  assertContract(Array.isArray(payload.comments), SCRIPT_TAG, 'issue payload must include a comments array');

  const comments = payload.comments
    .map((comment) => comment?.body)
    .filter((body) => typeof body === 'string' && body.trim().length > 0)
    .reverse();

  const closeout = comments.find((body) => {
    try {
      verifyCloseoutComment(body, { evidenceContext });
      return true;
    } catch {
      return false;
    }
  });

  assertContract(Boolean(closeout), SCRIPT_TAG, 'closed issue has no valid structured close-out evidence comment');
  return verifyCloseoutComment(closeout, {
    source: `issue #${payload.number ?? 'unknown'} close-out comment`,
    evidenceContext,
  });
}

function parsePositiveInteger(value, label, { max = Number.MAX_SAFE_INTEGER } = {}) {
  assertContract(value && /^\d+$/.test(value), SCRIPT_TAG, `Missing or invalid value for ${label}`);
  const parsed = Number(value);
  assertContract(parsed > 0, SCRIPT_TAG, `${label} must be greater than zero`);
  assertContract(parsed <= max, SCRIPT_TAG, `${label} must be <= ${max}`);
  return parsed;
}

function parseIssueList(value) {
  assertContract(value && typeof value === 'string', SCRIPT_TAG, 'Missing value for --issues');
  const issues = value
    .split(/[,\s]+/)
    .map((entry) => entry.trim())
    .filter(Boolean);
  assertContract(issues.length > 0, SCRIPT_TAG, '--issues must include at least one issue number');
  for (const issue of issues) {
    assertContract(/^\d+$/.test(issue), SCRIPT_TAG, `Invalid issue number in --issues: ${issue}`);
  }
  return Array.from(new Set(issues));
}

function parseArgs(argv) {
  const options = {
    contractOnly: false,
    closeoutFile: null,
    issue: null,
    issues: [],
    recentClosed: argv.length === 0 ? DEFAULT_RECENT_CLOSED_LIMIT : null,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === '--contract-only') {
      options.contractOnly = true;
      options.recentClosed = null;
      continue;
    }
    if (token === '--closeout-file') {
      const value = argv[index + 1];
      assertContract(value && !value.startsWith('--'), SCRIPT_TAG, 'Missing value for --closeout-file');
      options.closeoutFile = value;
      options.contractOnly = false;
      index += 1;
      continue;
    }
    if (token === '--issue') {
      const value = argv[index + 1];
      assertContract(value && /^\d+$/.test(value), SCRIPT_TAG, 'Missing or invalid value for --issue');
      options.issue = value;
      options.contractOnly = false;
      options.recentClosed = null;
      index += 1;
      continue;
    }
    if (token === '--issues') {
      const value = argv[index + 1];
      assertContract(value && !value.startsWith('--'), SCRIPT_TAG, 'Missing value for --issues');
      options.issues = parseIssueList(value);
      options.contractOnly = false;
      options.recentClosed = null;
      index += 1;
      continue;
    }
    if (token === '--recent-closed') {
      const value = argv[index + 1];
      options.recentClosed = parsePositiveInteger(value, '--recent-closed', { max: MAX_RECENT_CLOSED_LIMIT });
      options.contractOnly = false;
      index += 1;
      continue;
    }
    throw new Error(`${SCRIPT_TAG} Unknown argument: ${token}`);
  }

  assertContract(
    [
      options.contractOnly,
      Boolean(options.closeoutFile),
      Boolean(options.issue),
      options.issues.length > 0,
      options.recentClosed !== null,
    ].filter(Boolean).length === 1,
    SCRIPT_TAG,
    'Use exactly one mode: --contract-only, --closeout-file <path>, --issue <number>, --issues <numbers>, or --recent-closed <limit>',
  );

  return options;
}

function verifyContractOnly({ repoRoot }) {
  const issueLifecycle = fs.readFileSync(path.join(repoRoot, 'docs/execution/ISSUE_LIFECYCLE.md'), 'utf8');
  const contributing = fs.readFileSync(path.join(repoRoot, 'CONTRIBUTING.md'), 'utf8');
  const evidenceContext = createEvidenceContext({ repoRoot });
  const reachableCommit = resolveOriginMainCommit({ repoRoot });

  assertContract(
    issueLifecycle.includes('npm run verify:issue-lifecycle-evidence'),
    SCRIPT_TAG,
    'ISSUE_LIFECYCLE.md must document the issue lifecycle evidence verifier',
  );
  assertContract(
    issueLifecycle.includes('Evidence permalink'),
    SCRIPT_TAG,
    'ISSUE_LIFECYCLE.md must require an Evidence permalink field',
  );
  assertContract(
    contributing.includes('npm run verify:issue-lifecycle-evidence'),
    SCRIPT_TAG,
    'CONTRIBUTING.md must mention the issue lifecycle evidence verifier before issue close-out',
  );

  const sample = `## Outcome
Shipped the scoped cleanup and closed the issue.

## What changed
- Removed stale implementation paths.

## Verification
- npm run verify:repo-governance

## Risk / follow-up
- None.

- Evidence permalink: https://github.com/${evidenceContext.repoSlug}/issues/123#issuecomment-456
- Commit: ${reachableCommit}
`;
  verifyCloseoutComment(sample, { source: 'contract sample', evidenceContext });
}

function verifyCloseoutFile({ repoRoot, closeoutFile }) {
  const absolutePath = path.resolve(repoRoot, closeoutFile);
  assertContract(fs.existsSync(absolutePath), SCRIPT_TAG, `Missing close-out file: ${closeoutFile}`);
  const evidenceContext = createEvidenceContext({ repoRoot, refreshMain: true });
  return verifyCloseoutComment(fs.readFileSync(absolutePath, 'utf8'), { source: closeoutFile, evidenceContext });
}

function readIssuePayloadWithGh(issue) {
  let raw;
  try {
    raw = execFileSync('gh', ['issue', 'view', issue, '--json', 'number,state,comments'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
  } catch (error) {
    const stderr = error?.stderr ? String(error.stderr).trim() : '';
    throw new Error(`${SCRIPT_TAG} failed to read issue #${issue} with gh${stderr ? `: ${stderr}` : ''}`);
  }
  return JSON.parse(raw);
}

function readRecentClosedIssueNumbersWithGh(limit) {
  const repoSlug = resolveGitHubRepoSlug();
  const candidates = [];
  let page = 1;

  while (true) {
    let raw;
    try {
      raw = execFileSync('gh', [
        'api',
        `repos/${repoSlug}/issues?state=closed&sort=updated&direction=desc&per_page=${RECENT_CLOSED_PAGE_SIZE}&page=${page}`,
      ], {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'pipe'],
      });
    } catch (error) {
      const stderr = error?.stderr ? String(error.stderr).trim() : '';
      throw new Error(`${SCRIPT_TAG} failed to list recent closed issues with gh${stderr ? `: ${stderr}` : ''}`);
    }

    const issues = JSON.parse(raw);
    if (!Array.isArray(issues) || issues.length === 0) {
      break;
    }

    for (const issue of issues) {
      if (issue?.pull_request || !issue?.closed_at || !issue?.number) continue;
      candidates.push({
        number: issue.number,
        closedAt: issue.closed_at,
      });
    }

    const sortedCandidates = candidates
      .slice()
      .sort((a, b) => {
        const closedAtComparison = String(b.closedAt).localeCompare(String(a.closedAt));
        if (closedAtComparison !== 0) return closedAtComparison;
        return Number(b.number) - Number(a.number);
      });
    if (sortedCandidates.length >= limit) {
      const cutoffClosedAt = String(sortedCandidates[limit - 1].closedAt);
      const oldestUpdatedAtOnPage = String(issues.at(-1)?.updated_at ?? '');
      if (oldestUpdatedAtOnPage && cutoffClosedAt.localeCompare(oldestUpdatedAtOnPage) > 0) {
        break;
      }
    }

    page += 1;
  }

  return candidates
    .sort((a, b) => {
      const closedAtComparison = String(b.closedAt).localeCompare(String(a.closedAt));
      if (closedAtComparison !== 0) return closedAtComparison;
      return Number(b.number) - Number(a.number);
    })
    .slice(0, limit)
    .map((issue) => String(issue.number));
}

function verifyIssue({ issue, readIssuePayload = readIssuePayloadWithGh, evidenceContext = null }) {
  const payload = readIssuePayload(issue);
  assertContract(payload.state === 'CLOSED', SCRIPT_TAG, `issue #${issue} is not closed; close-out evidence is only checked for closed issues`);
  return verifyIssuePayload(payload, { evidenceContext });
}

function verifyIssueList({ issues, readIssuePayload = readIssuePayloadWithGh, evidenceContext = null }) {
  const results = issues.map((issue) => verifyIssue({ issue, readIssuePayload, evidenceContext }));
  return {
    ok: true,
    mode: 'issues',
    issues,
    results,
  };
}

function verifyRecentClosedIssues({
  limit,
  readIssuePayload = readIssuePayloadWithGh,
  readRecentClosedIssueNumbers = readRecentClosedIssueNumbersWithGh,
  evidenceContext = null,
}) {
  const issues = readRecentClosedIssueNumbers(limit);
  assertContract(
    Array.isArray(issues),
    SCRIPT_TAG,
    'recent closed issue reader must return an array of issue numbers',
  );
  return {
    ...verifyIssueList({ issues, readIssuePayload, evidenceContext }),
    mode: 'recent-closed',
    limit,
  };
}

export function verifyIssueLifecycleEvidence({
  argv = [],
  repoRoot = resolveRepoRootFromMeta(import.meta.url),
  readIssuePayload = readIssuePayloadWithGh,
  readRecentClosedIssueNumbers = readRecentClosedIssueNumbersWithGh,
  evidenceContext = null,
} = {}) {
  const options = parseArgs(argv);
  if (options.contractOnly) {
    verifyContractOnly({ repoRoot });
    return { ok: true, mode: 'contract-only' };
  }
  if (options.closeoutFile) {
    return verifyCloseoutFile({ repoRoot, closeoutFile: options.closeoutFile });
  }
  const issueEvidenceContext = evidenceContext ?? createEvidenceContext({ repoRoot, refreshMain: true });
  if (options.issue) {
    return verifyIssue({ issue: options.issue, readIssuePayload, evidenceContext: issueEvidenceContext });
  }
  if (options.issues.length > 0) {
    return verifyIssueList({ issues: options.issues, readIssuePayload, evidenceContext: issueEvidenceContext });
  }
  return verifyRecentClosedIssues({
    limit: options.recentClosed,
    readIssuePayload,
    readRecentClosedIssueNumbers,
    evidenceContext: issueEvidenceContext,
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runVerifierCli({
    scriptTag: SCRIPT_TAG,
    successMessage: 'Issue lifecycle evidence checks passed.',
    run: () => verifyIssueLifecycleEvidence({ argv: process.argv.slice(2) }),
  });
}
