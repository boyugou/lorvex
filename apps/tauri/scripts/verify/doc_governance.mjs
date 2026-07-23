#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  assertContract,
  resolveRepoRootFromMeta,
  runVerifierCli,
} from '../lib/verifier_runtime.mjs';
import { verifyBacktickedRepoPaths } from './backticked_repo_paths.mjs';

const SCRIPT_TAG = '[doc_governance]';

const REQUIRED_DOCS = [
  'docs/reference/REPO_FACTS.md',
];

const REQUIRED_REFERENCES = [
  {
    file: 'CLAUDE.md',
    references: ['docs/reference/REPO_FACTS.md'],
  },
  {
    file: 'CONTRIBUTING.md',
    references: ['docs/reference/REPO_FACTS.md'],
  },
];

const CANONICAL_REFERENCE_ROOTS = [
  'CLAUDE.md',
  'CONTRIBUTING.md',
  // The canonical getting-started doc lives at
  // `docs/setup/GETTING_STARTED.md`, covered by `'docs/setup'` below.
  // A repo-root `GETTING_STARTED.md` does not exist; pre-fix this list
  // silently referenced it (audit-pass-docs-finding-2).
  'README.md',
  'ROADMAP.md',
  'docs/INDEX.md',
  'docs/vision',
  'docs/design',
  'docs/execution',
  'docs/reference',
  'docs/setup',
];

const DATED_EXECUTION_REFERENCE_RE = /docs\/execution\/20\d{2}-\d{2}-\d{2}-[^\s)`'"]+\.md/g;
const FORBIDDEN_ARCHIVE_REFERENCE_RE = /docs\/archive\/(?!README\.md\b)[^\s)`'"]+|(?:\.\.\/)+archive\/[^\s)`'"]+|archive\/(?!README\.md\b)[^\s)`'"]+\.md/g;
const FORBIDDEN_CANONICAL_PROSE_RULES = [
  {
    pattern: /dated execution artifact/gi,
    description: 'dated execution artifact guidance',
    message: 'Canonical docs must not tell contributors to create dated execution artifacts; fold durable conclusions into canonical docs and keep one-off evidence in issue/PR comments, CI artifacts, or artifacts/manual-gates/.',
  },
];
const CANONICAL_DESIGN_STATUS_TAGS = new Set(['SHIPPED', 'PARTIAL', 'PLANNED', 'CUT']);
const DESIGN_STATUS_TAG_RE = /\[([A-Z][A-Z -]+)]/g;

function readFileOrThrow(absolutePath, displayPath) {
  assertContract(fs.existsSync(absolutePath), SCRIPT_TAG, `Missing required file: ${displayPath}`);
  return fs.readFileSync(absolutePath, 'utf8');
}

function toPosix(relativePath) {
  return relativePath.split(path.sep).join('/');
}

function collectFiles(absolutePath, results = []) {
  const stat = fs.statSync(absolutePath);
  if (stat.isFile()) {
    results.push(absolutePath);
    return results;
  }

  for (const entry of fs.readdirSync(absolutePath, { withFileTypes: true })) {
    const childPath = path.join(absolutePath, entry.name);
    if (entry.isDirectory()) {
      collectFiles(childPath, results);
      continue;
    }
    if (entry.isFile()) {
      results.push(childPath);
    }
  }
  return results;
}

function collectCanonicalMarkdownFiles(repoRoot) {
  return CANONICAL_REFERENCE_ROOTS.flatMap((relativePath) => {
    const absolutePath = path.join(repoRoot, relativePath);
    if (!fs.existsSync(absolutePath)) {
      return [];
    }
    return collectFiles(absolutePath).filter((filePath) => filePath.endsWith('.md'));
  });
}

export function collectUndefinedDesignStatusTags(content) {
  return Array.from(content.matchAll(DESIGN_STATUS_TAG_RE), (match) => match[1])
    .filter((tag) => !CANONICAL_DESIGN_STATUS_TAGS.has(tag));
}

function parseCanonicalCalendarEventTypes(schemaSql) {
  const checks = Array.from(
    schemaSql.matchAll(/CHECK\s*\(\s*event_type\s+IN\s*\(([^)]+)\)\s*\)/g),
    (match) => match[1],
  );
  assertContract(
    checks.length > 0,
    SCRIPT_TAG,
    'Could not find calendar event_type CHECK constraints in lorvex-store/src/schema/001_schema.sql',
  );

  const parsed = checks.map((check) =>
    Array.from(check.matchAll(/'([^']+)'/g), (match) => match[1]),
  );
  const canonical = parsed[0];
  assertContract(
    canonical.length > 0,
    SCRIPT_TAG,
    'Could not parse canonical calendar event_type values from schema CHECK constraint',
  );

  const drifted = parsed.find((values) => values.join('|') !== canonical.join('|'));
  assertContract(
    !drifted,
    SCRIPT_TAG,
    `Schema calendar event_type CHECK constraints disagree: expected ${canonical.join(', ')}, found ${drifted?.join(', ')}`,
  );
  return canonical;
}

function parseRoadmapCalendarEventTypes(roadmapBody) {
  const match = roadmapBody.match(/^- \[x\] Calendar event types:\s*([^\n.]+)(?:\.|\n)/m);
  assertContract(
    Boolean(match),
    SCRIPT_TAG,
    'ROADMAP.md must include a shipped "Calendar event types:" line that mirrors the schema allowlist.',
  );
  return match[1]
    .split(',')
    .map((value) => value.replaceAll('`', '').trim())
    .filter(Boolean);
}

export function verifyDocGovernance({
  repoRoot = resolveRepoRootFromMeta(import.meta.url),
} = {}) {
  verifyBacktickedRepoPaths({ repoRoot });

  for (const relativePath of REQUIRED_DOCS) {
    const absolutePath = path.join(repoRoot, relativePath);
    assertContract(fs.existsSync(absolutePath), SCRIPT_TAG, `Missing required governance doc: ${relativePath}`);
  }

  for (const rule of REQUIRED_REFERENCES) {
    const absolutePath = path.join(repoRoot, rule.file);
    const content = readFileOrThrow(absolutePath, rule.file);
    const missing = rule.references.filter((entry) => !content.includes(entry));
    assertContract(
      missing.length === 0,
      SCRIPT_TAG,
      `${rule.file} missing required reference(s): ${missing.join(', ')}`,
    );
  }

  // Governance rules for dated docs and repo-tracked plans are enforced
  // directly via CLAUDE.md norms; no separate DOC_LIFECYCLE.md needed.

  const executionDir = path.join(repoRoot, 'docs/execution');
  assertContract(fs.existsSync(executionDir), SCRIPT_TAG, 'Missing docs/execution directory');

  const plansDir = path.join(repoRoot, 'docs/plans');
  const executionDirEntries = fs.readdirSync(executionDir, { withFileTypes: true });
  const datedReports = executionDirEntries
    .filter((entry) => entry.isFile() && /^20\d{2}-\d{2}-\d{2}-.*\.md$/.test(entry.name))
    .map((entry) => entry.name)
    .sort((a, b) => a.localeCompare(b));
  const nonMarkdownExecutionFiles = executionDirEntries
    .filter((entry) => entry.isFile() && !entry.name.endsWith('.md'))
    .map((entry) => entry.name)
    .sort((a, b) => a.localeCompare(b));
  const topLevelExecutionTemplateDocs = executionDirEntries
    .filter((entry) => entry.isFile() && /template/i.test(entry.name) && entry.name.endsWith('.md'))
    .map((entry) => entry.name)
    .sort((a, b) => a.localeCompare(b));

  assertContract(
    datedReports.length === 0,
    SCRIPT_TAG,
    `Dated execution docs are forbidden in docs/execution: ${datedReports.map((name) => `docs/execution/${name}`).join(', ')}`,
  );

  const trackedPlanDocs = fs.existsSync(plansDir)
    ? collectFiles(plansDir)
      .filter((filePath) => filePath.endsWith('.md'))
      .map((filePath) => toPosix(path.relative(repoRoot, filePath)))
      .sort((a, b) => a.localeCompare(b))
    : [];
  assertContract(
    trackedPlanDocs.length === 0,
    SCRIPT_TAG,
    `Repo-tracked implementation plan docs are forbidden: ${trackedPlanDocs.join(', ')}`,
  );

  assertContract(
    topLevelExecutionTemplateDocs.length === 0,
    SCRIPT_TAG,
    `Top-level execution template docs are forbidden; move reusable templates under docs/execution/templates/: ${topLevelExecutionTemplateDocs.map((name) => `docs/execution/${name}`).join(', ')}`,
  );
  assertContract(
    nonMarkdownExecutionFiles.length === 0,
    SCRIPT_TAG,
    `docs/execution may only contain durable markdown docs at the top level; move artifacts elsewhere: ${nonMarkdownExecutionFiles.map((name) => `docs/execution/${name}`).join(', ')}`,
  );

  const gitignorePath = path.join(repoRoot, '.gitignore');
  const gitignore = readFileOrThrow(gitignorePath, '.gitignore');
  assertContract(
    gitignore.includes('artifacts/manual-gates/'),
    SCRIPT_TAG,
    '.gitignore must ignore artifacts/manual-gates/',
  );

  const docsIndexPath = path.join(repoRoot, 'docs/INDEX.md');
  const docsIndex = readFileOrThrow(docsIndexPath, 'docs/INDEX.md');
  const docsInventory = docsIndex.split('<!-- DOC_INVENTORY:START -->')[1] ?? '';
  assertContract(
    !/^### archive\//m.test(docsInventory),
    SCRIPT_TAG,
    'docs/INDEX auto-generated inventory must not surface archive/ as a primary reading path',
  );

  const activeMasterBacklogPath = path.join(repoRoot, 'docs/execution/MASTER_BACKLOG.md');
  assertContract(
    !fs.existsSync(activeMasterBacklogPath),
    SCRIPT_TAG,
    'docs/execution/MASTER_BACKLOG.md is archived and must not be restored as an active execution queue; use GitHub Issues for active backlog state.',
  );

  const schemaSql = readFileOrThrow(
    path.join(repoRoot, 'lorvex-store/src/schema/001_schema.sql'),
    'lorvex-store/src/schema/001_schema.sql',
  );
  const roadmap = readFileOrThrow(path.join(repoRoot, 'ROADMAP.md'), 'ROADMAP.md');
  const schemaEventTypes = parseCanonicalCalendarEventTypes(schemaSql);
  const roadmapEventTypes = parseRoadmapCalendarEventTypes(roadmap);
  assertContract(
    roadmapEventTypes.join('|') === schemaEventTypes.join('|'),
    SCRIPT_TAG,
    `ROADMAP.md calendar event types must mirror schema allowlist. Expected: ${schemaEventTypes.join(', ')}. Found: ${roadmapEventTypes.join(', ')}.`,
  );

  const canonicalFiles = collectCanonicalMarkdownFiles(repoRoot);
  const canonicalViolations = [];

  for (const absolutePath of canonicalFiles) {
    const relativePath = toPosix(path.relative(repoRoot, absolutePath));
    const content = readFileOrThrow(absolutePath, relativePath);
    if (relativePath !== 'docs/INDEX.md') {
      const archiveMatches = content.match(/(?:\.\.\/)*archive\/README\.md|docs\/archive\/README\.md/g);
      if (archiveMatches?.length) {
        canonicalViolations.push(`${relativePath} must not link to docs/archive/; only docs/INDEX.md may expose the archive entrypoint.`);
      }
    }
    const forbiddenArchiveMatches = content.match(FORBIDDEN_ARCHIVE_REFERENCE_RE);
    if (forbiddenArchiveMatches?.length) {
      canonicalViolations.push(
        `${relativePath} references forbidden archive path(s): ${Array.from(new Set(forbiddenArchiveMatches)).join(', ')}`,
      );
    }
    const datedReferenceMatches = content.match(DATED_EXECUTION_REFERENCE_RE);
    if (datedReferenceMatches?.length) {
      canonicalViolations.push(
        `${relativePath} references forbidden dated execution doc(s): ${Array.from(new Set(datedReferenceMatches)).join(', ')}`,
      );
    }

    for (const rule of FORBIDDEN_CANONICAL_PROSE_RULES) {
      if (rule.pattern.test(content)) {
        canonicalViolations.push(`${relativePath} contains forbidden ${rule.description}. ${rule.message}`);
      }
      rule.pattern.lastIndex = 0;
    }

    if (relativePath.startsWith('docs/design/')) {
      const undefinedStatusTags = Array.from(new Set(collectUndefinedDesignStatusTags(content))).sort(
        (a, b) => a.localeCompare(b),
      );
      if (undefinedStatusTags.length) {
        canonicalViolations.push(
          `${relativePath} uses undefined design status tag(s): ${undefinedStatusTags.map((tag) => `[${tag}]`).join(', ')}. Allowed tags: ${Array.from(CANONICAL_DESIGN_STATUS_TAGS, (tag) => `[${tag}]`).join(', ')}`,
        );
      }
    }
  }

  assertContract(
    canonicalViolations.length === 0,
    SCRIPT_TAG,
    `Canonical docs violate documentation governance:\n- ${canonicalViolations.join('\n- ')}`,
  );

  return {
    ok: true,
    canonicalMarkdownFilesChecked: canonicalFiles.length,
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runVerifierCli({
    scriptTag: SCRIPT_TAG,
    successMessage: 'Documentation governance checks passed.',
    run: () => verifyDocGovernance(),
  });
}
