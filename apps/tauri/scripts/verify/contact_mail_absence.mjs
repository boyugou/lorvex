#!/usr/bin/env node

/**
 * Verifier: contact-mail absence
 *
 * Enforces CLAUDE.md Core Design Rule #9: Lorvex has no email mailbox. Every
 * contact-bearing surface must route through GitHub (private security
 * advisories for security/conduct, public issue templates otherwise).
 *
 * This gate fails when:
 *
 *   1. Any tracked contact-bearing file contains an `@lorvex.app` literal.
 *      The scanned surfaces include the contact root docs (SECURITY.md,
 *      SUPPORT.md, CODE_OF_CONDUCT.md, README.md), the in-app i18n catalogs,
 *      the user-facing docs, and the Tauri Rust sources (where user-facing
 *      error-toast strings live).
 *
 *   2. SECURITY.md does not link to the GitHub private security advisories
 *      URL (`<repo>/security/advisories/new`). The doc is the canonical entry
 *      point for the GitHub-only contact contract; if the link disappears,
 *      vulnerability reporters lose the only valid channel.
 *
 * Two files are intentionally exempt because they describe the policy itself
 * rather than create a contact path: CLAUDE.md (which spells out rule #9)
 * and CHANGELOG.md (which records the rule's introduction). Both reference
 * `@lorvex.app` only inside a "no mailbox exists" sentence; flagging them
 * would force the policy text to elide the literal it forbids.
 *
 * Issue #4096 tracks the eventual provisioning of a real mailbox; until that
 * lands and contact docs are updated, every email reference here is a
 * regression.
 */

import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

import {
  assertContract,
  resolveRepoRootFromMeta,
} from '../lib/verifier_runtime.mjs';

const SCRIPT_TAG = '[verify:contact-mail-absence]';
const FORBIDDEN_LITERAL = '@lorvex.app';
const ADVISORIES_URL_FRAGMENT = 'security/advisories/new';

// Files that document the GitHub-only contact policy itself. They legitimately
// reference the forbidden literal inside policy text ("no @lorvex.app mailbox
// exists"); scanning them would force a self-contradicting policy statement.
const POLICY_DOCS_EXEMPT = new Set([
  'CLAUDE.md',
  'CHANGELOG.md',
]);

// Curated set of contact-bearing surfaces. Each entry maps a relative path
// (or directory + extension filter) to its role. Adding a new contact surface
// (a new locale catalog, a new platform's about page)
// means adding it here so the gate keeps up with the contact perimeter.
const SCAN_TARGETS = [
  { path: 'SECURITY.md', role: 'security contact root' },
  { path: 'SUPPORT.md', role: 'support contact root' },
  { path: 'CODE_OF_CONDUCT.md', role: 'conduct contact root' },
  { path: 'README.md', role: 'project README' },
  { path: 'CONTRIBUTING.md', role: 'contributor contact surface' },
  { directory: 'app/src/locales', extensions: ['.json'], role: 'in-app i18n catalog' },
  { directory: 'app/src-tauri/src', extensions: ['.rs'], role: 'Tauri Rust source (error toasts)' },
  { directory: 'app/src', extensions: ['.tsx', '.ts'], role: 'desktop frontend source' },
];

function walk(rootAbsolute, extensions) {
  if (!fs.existsSync(rootAbsolute)) return [];
  const results = [];
  for (const entry of fs.readdirSync(rootAbsolute, { withFileTypes: true })) {
    const full = path.join(rootAbsolute, entry.name);
    if (entry.isDirectory()) {
      if (entry.name === 'node_modules' || entry.name === 'target' || entry.name === '.git') {
        continue;
      }
      results.push(...walk(full, extensions));
    } else if (entry.isFile() && extensions.some((ext) => entry.name.endsWith(ext))) {
      results.push(full);
    }
  }
  return results;
}

function collectFiles(repoRoot) {
  const files = [];
  for (const target of SCAN_TARGETS) {
    if (target.path) {
      const absolute = path.join(repoRoot, target.path);
      if (fs.existsSync(absolute)) {
        files.push({ absolute, relative: target.path, role: target.role });
      }
      continue;
    }
    const absoluteDir = path.join(repoRoot, target.directory);
    for (const absolute of walk(absoluteDir, target.extensions)) {
      const relative = path.relative(repoRoot, absolute).split(path.sep).join('/');
      files.push({ absolute, relative, role: target.role });
    }
  }
  return files;
}

function findForbiddenLiteralOccurrences(repoRoot) {
  const findings = [];
  for (const file of collectFiles(repoRoot)) {
    if (POLICY_DOCS_EXEMPT.has(file.relative)) continue;
    const source = fs.readFileSync(file.absolute, 'utf8');
    const lines = source.split('\n');
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].includes(FORBIDDEN_LITERAL)) {
        findings.push({
          file: file.relative,
          role: file.role,
          line: i + 1,
          text: lines[i].trim(),
        });
      }
    }
  }
  return findings;
}

function assertAdvisoryLink(repoRoot) {
  const securityPath = path.join(repoRoot, 'SECURITY.md');
  assertContract(
    fs.existsSync(securityPath),
    SCRIPT_TAG,
    'SECURITY.md must exist as the GitHub-only security contact entry point',
  );
  const source = fs.readFileSync(securityPath, 'utf8');
  assertContract(
    source.includes(ADVISORIES_URL_FRAGMENT),
    SCRIPT_TAG,
    `SECURITY.md must link to the GitHub private security advisories URL (contains "${ADVISORIES_URL_FRAGMENT}")`,
  );
}

export function verifyContactMailAbsence({
  repoRoot = resolveRepoRootFromMeta(import.meta.url),
} = {}) {
  assertAdvisoryLink(repoRoot);

  const findings = findForbiddenLiteralOccurrences(repoRoot);
  if (findings.length > 0) {
    const detail = findings
      .map((f) => `  ${f.file}:${f.line}  [${f.role}]  ${f.text}`)
      .join('\n');
    throw new Error(
      `${SCRIPT_TAG} Found ${findings.length} ${FORBIDDEN_LITERAL} reference(s) in contact-bearing files.\n` +
        `Per CLAUDE.md Core Design Rule #9 no @lorvex.app mailbox exists; every contact path must route\n` +
        `through GitHub. Replace with the GitHub private security advisories URL (security/conduct) or\n` +
        `the public issue template URL (support/feedback). See issue #4096 for the future mailbox plan.\n\n` +
        detail,
    );
  }
}

function main() {
  try {
    verifyContactMailAbsence();
    console.log(`${SCRIPT_TAG} OK — no @lorvex.app references in scanned contact surfaces`);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    console.error(message.startsWith(SCRIPT_TAG) ? message : `${SCRIPT_TAG} ${message}`);
    process.exit(1);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
