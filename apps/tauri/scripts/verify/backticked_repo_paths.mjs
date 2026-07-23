#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  assertContract,
  resolveRepoRootFromMeta,
  runVerifierCli,
} from '../lib/verifier_runtime.mjs';

const SCRIPT_TAG = '[verify:backticked-repo-paths]';

const ACTIVE_DOC_ROOTS = [
  'CLAUDE.md',
  'CONTRIBUTING.md',
  'README.md',
  'ROADMAP.md',
  'docs/INDEX.md',
  'docs/vision',
  'docs/design',
  'docs/execution',
  'docs/reference',
  'docs/setup',
];

const REPO_PATH_ROOTS = [
  '.github',
  'app',
  'cloudkit',
  'docs',
  'lorvex-cli',
  'lorvex-domain',
  'lorvex-mcp-derive',
  'lorvex-runtime',
  'lorvex-store',
  'lorvex-sync',
  'lorvex-workflow',
  'mcp-server',
  'scripts',
  'shared',
  'skill',
];

const GENERATED_OUTPUT_SEGMENTS = new Set([
  'artifacts',
  'bin',
  'dist',
  'node_modules',
  'target',
]);

const LOCAL_ONLY_SETUP_PATHS = new Set([]);

const INLINE_CODE_RE = /`([^`\n]+)`/g;
const FENCED_CODE_RE = /```[\s\S]*?```|~~~[\s\S]*?~~~/g;

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

function collectActiveMarkdownFiles(repoRoot, roots = ACTIVE_DOC_ROOTS) {
  return roots.flatMap((relativePath) => {
    const absolutePath = path.join(repoRoot, relativePath);
    if (!fs.existsSync(absolutePath)) {
      return [];
    }
    return collectFiles(absolutePath).filter((filePath) => filePath.endsWith('.md'));
  });
}

function stripFencedCodeBlocks(markdown) {
  return markdown.replace(FENCED_CODE_RE, (block) => '\n'.repeat(block.split('\n').length - 1));
}

function isRepoPathCandidate(value) {
  if (!value.includes('/')) {
    return false;
  }
  if (/[\s"'|;&()]/.test(value)) {
    return false;
  }
  if (/^[a-z][a-z0-9+.-]*:/i.test(value)) {
    return false;
  }
  if (value.startsWith('/') || value.startsWith('~/') || value.startsWith('$')) {
    return false;
  }
  return REPO_PATH_ROOTS.some((root) => value === root || value.startsWith(`${root}/`));
}

function isAllowedNonMaterializedPath(value) {
  if (LOCAL_ONLY_SETUP_PATHS.has(value)) {
    return true;
  }
  if (/[{}*?[\]]/.test(value)) {
    return true;
  }
  if (value.includes('<') || value.includes('>') || value.includes('...')) {
    return true;
  }
  if (value.startsWith('docs/archive/')) {
    return true;
  }

  const segments = value.split('/');
  return segments.some((segment) => GENERATED_OUTPUT_SEGMENTS.has(segment));
}

function normalizeCandidate(rawValue) {
  return rawValue
    .trim()
    .replace(/^\.\/+/, '')
    .replace(/[.,:;]+$/g, '');
}

function lineForOffset(source, offset) {
  return source.slice(0, offset).split('\n').length;
}

function collectBacktickedRepoPathViolations({
  repoRoot = resolveRepoRootFromMeta(import.meta.url),
  includeRoots = ACTIVE_DOC_ROOTS,
} = {}) {
  const files = collectActiveMarkdownFiles(repoRoot, includeRoots);
  const violations = [];
  let checked = 0;

  for (const filePath of files) {
    const relativeFilePath = toPosix(path.relative(repoRoot, filePath));
    const source = fs.readFileSync(filePath, 'utf8');
    const sourceWithoutBlocks = stripFencedCodeBlocks(source);

    for (const match of sourceWithoutBlocks.matchAll(INLINE_CODE_RE)) {
      const candidate = normalizeCandidate(match[1] ?? '');
      if (!isRepoPathCandidate(candidate) || isAllowedNonMaterializedPath(candidate)) {
        continue;
      }

      checked += 1;
      const absoluteCandidatePath = path.join(repoRoot, candidate);
      if (!fs.existsSync(absoluteCandidatePath)) {
        const line = lineForOffset(sourceWithoutBlocks, match.index ?? 0);
        violations.push(`${relativeFilePath}:${line} -> \`${candidate}\``);
      }
    }
  }

  return {
    filesChecked: files.length,
    backtickedPathsChecked: checked,
    violations,
  };
}

export function verifyBacktickedRepoPaths({
  repoRoot = resolveRepoRootFromMeta(import.meta.url),
  includeRoots = ACTIVE_DOC_ROOTS,
} = {}) {
  const result = collectBacktickedRepoPathViolations({ repoRoot, includeRoots });
  assertContract(
    result.violations.length === 0,
    SCRIPT_TAG,
    `Backticked repo path(s) do not exist in active docs:\n- ${result.violations.join('\n- ')}`,
  );

  return {
    ok: true,
    filesChecked: result.filesChecked,
    backtickedPathsChecked: result.backtickedPathsChecked,
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runVerifierCli({
    scriptTag: SCRIPT_TAG,
    successMessage: 'Backticked repo path checks passed.',
    run: () => verifyBacktickedRepoPaths(),
  });
}
