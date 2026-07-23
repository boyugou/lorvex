#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  MANUAL_GATE_FRESHNESS_DAYS,
  TEMPLATE_SPECS,
  manualGateOutputDirFromEnv,
  resolveManualGateOutputRoot,
} from '../manual-gate/templates.mjs';
import { resolveGitHubRepoSlug } from './issue_lifecycle_evidence.mjs';

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const COMMIT_RE = /^[0-9a-f]{7,40}(?:-dirty)?$/i;
const GITHUB_ISSUE_OR_PR_PERMALINK_RE =
  /^https:\/\/github\.com\/([^/\s]+)\/([^/\s]+)\/(?:issues|pull)\/\d+#(?:issuecomment-\d+|discussion_r\d+)$/;
const ISO_UTC_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const TARGET_SLUG_RE = /^(?:issue-\d+|pr-\d+|release-[A-Za-z0-9][A-Za-z0-9._-]{0,119})$/;

const GATE_SPECS = [
  {
    id: 'mcp-e2e',
    slug: 'mcp-e2e',
    requiredHeadings: TEMPLATE_SPECS['mcp-e2e'].requiredHeadings,
  },
  {
    id: 'ui-regression',
    slug: 'ui-regression',
    requiredHeadings: TEMPLATE_SPECS['ui-regression'].requiredHeadings,
  },
  {
    id: 'sync-recovery',
    slug: 'sync-recovery',
    requiredHeadings: TEMPLATE_SPECS['sync-recovery'].requiredHeadings,
  },
];

function fail(message) {
  console.error(`[manual_gate_evidence] ERROR: ${message}`);
  process.exit(1);
}

function toPosix(relativePath) {
  return relativePath.split(path.sep).join('/');
}

function parseArgs(argv) {
  const options = {
    enforceRelease: false,
    maxAgeDays: MANUAL_GATE_FRESHNESS_DAYS,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === '--enforce-release') {
      options.enforceRelease = true;
      continue;
    }
    if (token === '--max-age-days') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) {
        fail('Missing value for --max-age-days');
      }
      const parsed = Number.parseInt(value, 10);
      if (!Number.isInteger(parsed) || parsed <= 0) {
        fail(`Invalid --max-age-days value: ${value}`);
      }
      options.maxAgeDays = parsed;
      index += 1;
      continue;
    }
    fail(`Unknown argument: ${token}`);
  }

  return options;
}

function parseDateAtUtcStart(date) {
  if (!DATE_RE.test(date)) return null;
  const parsed = new Date(`${date}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime())) return null;
  return parsed;
}

function ageDaysFromNow(date, now) {
  const parsed = parseDateAtUtcStart(date);
  if (!parsed) return Number.NaN;
  return Math.floor((now.getTime() - parsed.getTime()) / (24 * 60 * 60 * 1000));
}

function fieldValue(content, fieldLabel) {
  const escaped = fieldLabel.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = content.match(new RegExp(`^- ${escaped}:\\s*(.+)$`, 'm'));
  return match?.[1]?.trim() ?? null;
}

function isPlaceholder(value) {
  if (!value) return true;
  if (value.includes('{{') || value.includes('}}')) return true;
  if (/^<[^>]+>$/.test(value)) return true;
  if (value.includes('<') && value.includes('>')) return true;
  return false;
}

function isNoBlockingDefects(value) {
  return value.trim().toLowerCase() === 'none';
}

function evidenceTargetToSlug(value) {
  const issueMatch = value.match(/^issue #(\d+)$/i);
  if (issueMatch) return `issue-${issueMatch[1]}`;

  const prMatch = value.match(/^PR #(\d+)$/i);
  if (prMatch) return `pr-${prMatch[1]}`;

  const releaseMatch = value.match(/^release ([A-Za-z0-9][A-Za-z0-9._-]{0,119})$/);
  if (releaseMatch) return `release-${releaseMatch[1]}`;

  return null;
}

function normalizeRepoSlug(value) {
  return value.trim().toLowerCase();
}

function repoSlugFromEvidencePermalink(value) {
  const match = value.match(GITHUB_ISSUE_OR_PR_PERMALINK_RE);
  return match ? normalizeRepoSlug(`${match[1]}/${match[2]}`) : null;
}

function requireField(content, label) {
  const value = fieldValue(content, label);
  if (!value) {
    throw new Error(`missing required field line: "- ${label}: ..."`);
  }
  if (isPlaceholder(value)) {
    throw new Error(`field "${label}" still contains placeholder text: ${value}`);
  }
  return value;
}

function collectReports(rootDir, baseDir = rootDir) {
  if (!fs.existsSync(rootDir)) {
    return [];
  }

  return fs.readdirSync(rootDir, { withFileTypes: true }).flatMap((entry) => {
    const absolutePath = path.join(rootDir, entry.name);
    if (entry.isDirectory()) {
      return collectReports(absolutePath, baseDir);
    }
    if (!entry.isFile()) {
      return [];
    }

    const relativePath = toPosix(path.relative(baseDir, absolutePath));
    const parts = relativePath.split('/');
    const fileName = parts.at(-1);
    const date = parts.at(-2);
    const slug = parts.at(-3);
    if (!fileName || !date || !slug || !fileName.endsWith('.md') || !DATE_RE.test(date)) {
      return [];
    }
    const targetSlug = fileName.slice(0, -'.md'.length);
    if (!TARGET_SLUG_RE.test(targetSlug)) {
      return [];
    }
    return [{
      date,
      slug,
      targetSlug,
      absolutePath,
      relativePath,
    }];
  });
}

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), '..', '..');
const evidenceDir = resolveManualGateOutputRoot(repoRoot);
const evidenceDirDisplay = manualGateOutputDirFromEnv();
const options = parseArgs(process.argv.slice(2));
const now = new Date();
let repoSlug = null;

function displayReportPath(report) {
  const repoRelative = path.relative(repoRoot, report.absolutePath);
  if (repoRelative && !repoRelative.startsWith('..') && !path.isAbsolute(repoRelative)) {
    return toPosix(repoRelative);
  }
  return report.relativePath;
}

function currentRepoSlug() {
  repoSlug ??= resolveGitHubRepoSlug({ repoRoot });
  return repoSlug;
}

if (!fs.existsSync(evidenceDir)) {
  if (options.enforceRelease) {
    fail(`Missing manual gate evidence directory: ${evidenceDirDisplay}`);
  }
  console.warn(`[manual_gate_evidence] WARN: manual gate evidence directory not found: ${evidenceDirDisplay}`);
}

const reports = collectReports(evidenceDir);
let checkedCount = 0;
const warnings = [];

for (const gate of GATE_SPECS) {
  const matches = reports
    .filter((report) => report.slug === gate.slug)
    .sort((a, b) => a.date.localeCompare(b.date) || a.relativePath.localeCompare(b.relativePath));

  if (matches.length === 0) {
    const message = `${gate.id}: no evidence reports found under ${evidenceDirDisplay} (expected pattern ${gate.slug}/YYYY-MM-DD/<issue-N|pr-N|release-id>.md)`;
    if (options.enforceRelease) {
      fail(message);
    }
    warnings.push(message);
    continue;
  }

  const latest = matches[matches.length - 1];
  const reportPath = latest.absolutePath;
  const relativePath = displayReportPath(latest);
  const content = fs.readFileSync(reportPath, 'utf8');

  if (content.includes('{{') || content.includes('}}')) {
    fail(`${relativePath}: unresolved template placeholders detected`);
  }

  for (const heading of gate.requiredHeadings) {
    if (!content.includes(heading)) {
      fail(`${relativePath}: missing required heading from template contract: ${heading}`);
    }
  }

  let evidenceTargetValue;
  let dateValue;
  let commitValue;
  let statusValue;
  let blockingValue;
  let capturedAtValue;
  let freshUntilValue;
  let ownerValue;
  let evidencePermalinkValue;
  try {
    evidenceTargetValue = requireField(content, 'Evidence target');
    dateValue = requireField(content, 'Date');
    commitValue = requireField(content, 'Build commit');
    evidencePermalinkValue = requireField(content, 'Evidence permalink');
    statusValue = requireField(content, 'Status');
    blockingValue = requireField(content, 'Blocking defects');
    capturedAtValue = requireField(content, 'Captured at (UTC)');
    freshUntilValue = requireField(content, 'Fresh until (UTC)');
    ownerValue = requireField(content, 'Evidence owner');
  } catch (error) {
    fail(`${relativePath}: ${(error instanceof Error ? error.message : String(error))}`);
  }

  const evidenceTargetSlug = evidenceTargetToSlug(evidenceTargetValue);
  if (!evidenceTargetSlug) {
    fail(`${relativePath}: Evidence target must be "issue #N", "PR #N", or "release ID", got ${evidenceTargetValue}`);
  }
  if (evidenceTargetSlug !== latest.targetSlug) {
    fail(`${relativePath}: Evidence target (${evidenceTargetValue}) must match filename target (${latest.targetSlug})`);
  }

  if (!DATE_RE.test(dateValue)) {
    fail(`${relativePath}: Date field must be YYYY-MM-DD, got ${dateValue}`);
  }

  if (dateValue !== latest.date) {
    fail(`${relativePath}: Date field (${dateValue}) must match filename date (${latest.date})`);
  }

  if (!COMMIT_RE.test(commitValue)) {
    fail(`${relativePath}: Build commit must look like git SHA (7-40 hex, optional -dirty), got ${commitValue}`);
  }

  if (!GITHUB_ISSUE_OR_PR_PERMALINK_RE.test(evidencePermalinkValue)) {
    fail(`${relativePath}: Evidence permalink must be a GitHub issue/PR comment permalink, got ${evidencePermalinkValue}`);
  }
  const expectedRepoSlug = currentRepoSlug();
  if (repoSlugFromEvidencePermalink(evidencePermalinkValue) !== normalizeRepoSlug(expectedRepoSlug)) {
    fail(`${relativePath}: Evidence permalink must belong to this repository (${expectedRepoSlug}), got ${evidencePermalinkValue}`);
  }

  if (!['PASS', 'PARTIAL', 'FAIL'].includes(statusValue)) {
    fail(`${relativePath}: Status must be PASS, PARTIAL, or FAIL (got ${statusValue})`);
  }

  if (!ISO_UTC_RE.test(capturedAtValue)) {
    fail(`${relativePath}: Captured at (UTC) must be ISO UTC without millis, got ${capturedAtValue}`);
  }

  if (!ISO_UTC_RE.test(freshUntilValue)) {
    fail(`${relativePath}: Fresh until (UTC) must be ISO UTC without millis, got ${freshUntilValue}`);
  }

  const capturedAt = new Date(capturedAtValue);
  const freshUntil = new Date(freshUntilValue);
  if (Number.isNaN(capturedAt.getTime())) {
    fail(`${relativePath}: invalid Captured at (UTC) value: ${capturedAtValue}`);
  }
  if (Number.isNaN(freshUntil.getTime())) {
    fail(`${relativePath}: invalid Fresh until (UTC) value: ${freshUntilValue}`);
  }
  if (freshUntil.getTime() <= capturedAt.getTime()) {
    fail(`${relativePath}: Fresh until (UTC) must be later than Captured at (UTC)`);
  }

  const ageDays = ageDaysFromNow(latest.date, now);
  if (!Number.isFinite(ageDays)) {
    fail(`${relativePath}: cannot compute age from date ${latest.date}`);
  }

  if (options.enforceRelease) {
    if (statusValue !== 'PASS') {
      fail(`${relativePath}: release enforcement requires Status: PASS (got ${statusValue})`);
    }
    if (!isNoBlockingDefects(blockingValue)) {
      fail(`${relativePath}: release enforcement requires Blocking defects: none (got ${blockingValue})`);
    }
    if (ageDays > options.maxAgeDays) {
      fail(`${relativePath}: evidence age ${ageDays}d exceeds max ${options.maxAgeDays}d`);
    }
    if (freshUntil.getTime() < now.getTime()) {
      fail(`${relativePath}: Fresh until (UTC) ${freshUntilValue} is expired`);
    }
  } else if (ageDays > options.maxAgeDays) {
    warnings.push(`${gate.id}: latest evidence (${relativePath}) is stale (${ageDays}d > ${options.maxAgeDays}d)`);
  }

  checkedCount += 1;
  console.log(
    `[manual_gate_evidence] OK: ${gate.id} -> ${relativePath} (target=${evidenceTargetValue}, status=${statusValue}, age=${ageDays}d, owner=${ownerValue}, blocking=${blockingValue}, permalink=${evidencePermalinkValue})`,
  );
}

for (const warning of warnings) {
  console.warn(`[manual_gate_evidence] WARN: ${warning}`);
}

if (options.enforceRelease) {
  console.log(`[manual_gate_evidence] OK: release enforcement passed (${checkedCount}/${GATE_SPECS.length} gate report(s) checked)`);
} else {
  console.log(`[manual_gate_evidence] OK: non-release check completed (${checkedCount}/${GATE_SPECS.length} gate report(s) checked)`);
}
