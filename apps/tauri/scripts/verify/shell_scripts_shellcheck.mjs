#!/usr/bin/env node

// Audit #2329: run shellcheck against every tracked `*.sh` so
// unquoted $VAR, `rm -rf $EMPTY_VAR`, and similar shell bugs get
// caught in verify before they ship. Local checkouts may skip when
// shellcheck is not installed, but GitHub Actions must fail closed so
// the canonical static gate cannot pass without actually linting shell
// scripts.

import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), '..', '..');

function fail(message) {
  console.error(`[verify:shellcheck] ${message}`);
  process.exit(1);
}

const which = spawnSync('shellcheck', ['--version'], { stdio: 'ignore' });
if (which.status !== 0) {
  if (process.env.GITHUB_ACTIONS === 'true') {
    fail('shellcheck is required in GitHub Actions; install shellcheck before running verify:shellcheck.');
  }
  console.warn('[verify:shellcheck] shellcheck not available locally; skipping. Install shellcheck to run this gate before CI.');
  process.exit(0);
}

const lsFiles = spawnSync(
  'git',
  ['ls-files', '*.sh'],
  { cwd: repoRoot, encoding: 'utf8' },
);
if (lsFiles.status !== 0) {
  fail(`git ls-files failed: ${lsFiles.stderr || 'unknown error'}`);
}
const files = lsFiles.stdout.split('\n').filter(Boolean);
if (files.length === 0) {
  console.log('[verify:shellcheck] no shell scripts tracked; OK.');
  process.exit(0);
}

// Severity gate: warning+. Style-level nits (info/style) don't fail
// the gate so we can adopt shellcheck incrementally without a
// cleanup-first migration.
const result = spawnSync(
  'shellcheck',
  ['--severity=warning', '--shell=bash', ...files],
  { cwd: repoRoot, stdio: 'inherit' },
);
if (result.error) {
  fail(`failed to invoke shellcheck: ${result.error.message}`);
}
if (typeof result.status === 'number' && result.status !== 0) {
  fail(`shellcheck reported issues in ${files.length} tracked script(s).`);
}

console.log(`[verify:shellcheck] OK (${files.length} script(s)).`);
