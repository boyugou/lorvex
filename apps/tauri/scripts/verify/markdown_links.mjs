#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  assertContract,
  resolveRepoRootFromMeta,
  runVerifierCli,
} from '../lib/verifier_runtime.mjs';

const SCRIPT_TAG = '[verify:markdown-links]';
const DEFAULT_INCLUDE_ROOTS = [
  'CLAUDE.md',
  'CONTRIBUTING.md',
  'ROADMAP.md',
  // The canonical getting-started doc lives at `docs/setup/GETTING_STARTED.md`,
  // covered by the `'docs'` directory walk below. A repo-root
  // `GETTING_STARTED.md` does not exist; pre-fix this list silently
  // referenced it (audit-pass-docs-finding-2).
  'docs',
  '.github',
];
const IGNORED_SCHEMES = ['app://', 'data:', 'http://', 'https://', 'mailto:', 'tel:'];
const MARKDOWN_LINK_RE = /!?\[[^\]]*]\(([^)]+)\)/g;
const YAML_URL_RE = /^\s*url:\s*['"]?([^'"\s#]+)['"]?\s*$/gm;

function toPosix(relativePath) {
  return relativePath.split(path.sep).join('/');
}

function collectFiles(targetPath, results = []) {
  const stat = fs.statSync(targetPath);
  if (stat.isFile()) {
    results.push(targetPath);
    return results;
  }

  for (const entry of fs.readdirSync(targetPath, { withFileTypes: true })) {
    const childPath = path.join(targetPath, entry.name);
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

function resolveIncludedLinkFiles(repoRoot, include) {
  return include.flatMap((relativePath) => {
    const absolutePath = path.join(repoRoot, relativePath);
    if (!fs.existsSync(absolutePath)) {
      return [];
    }
    return collectFiles(absolutePath).filter((filePath) =>
      filePath.endsWith('.md') || filePath.endsWith('.yml') || filePath.endsWith('.yaml'),
    );
  });
}

function normalizeLinkTarget(rawTarget) {
  let target = rawTarget.trim();
  if (target.startsWith('<') && target.endsWith('>')) {
    target = target.slice(1, -1).trim();
  }
  const titleMatch = target.match(/^(\S+)\s+".*"$/);
  if (titleMatch) {
    target = titleMatch[1];
  }
  return target;
}

function isIgnoredLink(target) {
  return target.startsWith('#') || IGNORED_SCHEMES.some((scheme) => target.startsWith(scheme));
}

function readOriginSlug(repoRoot) {
  const gitPath = path.join(repoRoot, '.git');
  if (!fs.existsSync(gitPath) || !fs.statSync(gitPath).isDirectory()) {
    return null;
  }

  const configPath = path.join(gitPath, 'config');
  if (!fs.existsSync(configPath)) {
    return null;
  }

  const config = fs.readFileSync(configPath, 'utf8');
  const match = config.match(/\[remote "origin"][\s\S]*?\n\s*url\s*=\s*(\S+)/);
  if (!match) {
    return null;
  }

  const rawUrl = match[1].replace(/\.git$/, '');
  const sshMatch = rawUrl.match(/^git@github\.com:([^/]+\/[^/]+)$/);
  if (sshMatch) {
    return sshMatch[1];
  }
  const httpsMatch = rawUrl.match(/^https:\/\/github\.com\/([^/]+\/[^/]+)$/);
  return httpsMatch?.[1] ?? null;
}

function githubBlobTarget(target) {
  let parsed;
  try {
    parsed = new URL(target);
  } catch {
    return null;
  }
  if (parsed.hostname !== 'github.com') {
    return null;
  }

  const parts = parsed.pathname.split('/').filter(Boolean);
  const blobIndex = parts.indexOf('blob');
  if (blobIndex !== 2 || parts.length <= 4) {
    return null;
  }
  return {
    slug: `${parts[0]}/${parts[1]}`,
    repoPath: parts.slice(4).join('/'),
  };
}

function extractTargets(filePath, content) {
  if (filePath.endsWith('.md')) {
    return Array.from(content.matchAll(MARKDOWN_LINK_RE), (match) =>
      normalizeLinkTarget(match[1] ?? ''),
    );
  }

  return Array.from(content.matchAll(YAML_URL_RE), (match) => normalizeLinkTarget(match[1] ?? ''));
}

export function verifyMarkdownLinks({
  repoRoot = resolveRepoRootFromMeta(import.meta.url),
  include,
} = {}) {
  const linkFiles = resolveIncludedLinkFiles(
    repoRoot,
    include ?? resolveDefaultInclude(repoRoot),
  );
  const brokenLinks = [];
  const originSlug = readOriginSlug(repoRoot);

  for (const filePath of linkFiles) {
    const relativeFilePath = toPosix(path.relative(repoRoot, filePath));
    const content = fs.readFileSync(filePath, 'utf8');

    for (const target of extractTargets(filePath, content)) {
      if (!target) continue;

      const githubBlob = githubBlobTarget(target);
      if (githubBlob) {
        if (originSlug && githubBlob.slug !== originSlug) {
          brokenLinks.push(`${relativeFilePath} -> ${target} (expected GitHub repo ${originSlug})`);
          continue;
        }
        const resolvedPath = path.join(repoRoot, githubBlob.repoPath);
        if (!fs.existsSync(resolvedPath)) {
          brokenLinks.push(`${relativeFilePath} -> ${target}`);
        }
        continue;
      }

      if (isIgnoredLink(target)) continue;

      const [pathPart] = target.split('#', 1);
      if (!pathPart) continue;

      const resolvedPath = target.startsWith('/')
        ? path.join(repoRoot, pathPart.slice(1))
        : path.resolve(path.dirname(filePath), pathPart);

      if (!fs.existsSync(resolvedPath)) {
        brokenLinks.push(`${relativeFilePath} -> ${target}`);
      }
    }
  }

  assertContract(
    brokenLinks.length === 0,
    SCRIPT_TAG,
    `Broken repo-local markdown link(s):\n- ${brokenLinks.join('\n- ')}`,
  );

  return {
    ok: true,
    filesChecked: linkFiles.length,
  };
}

function resolveDefaultInclude(repoRoot) {
  const rootReadmes = fs.readdirSync(repoRoot, { withFileTypes: true })
    .filter((entry) => entry.isFile() && /^README(?:\.[^.]+)*\.md$/i.test(entry.name))
    .map((entry) => entry.name)
    .sort((a, b) => a.localeCompare(b));

  return [...new Set([...DEFAULT_INCLUDE_ROOTS, ...rootReadmes])];
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  runVerifierCli({
    scriptTag: SCRIPT_TAG,
    successMessage: 'Markdown link checks passed.',
    run: () => verifyMarkdownLinks(),
  });
}
