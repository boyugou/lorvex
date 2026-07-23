#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

function fail(message) {
  console.error(`[verify:dev-session-preflight] ${message}`);
  process.exit(1);
}

function assert(condition, message) {
  if (!condition) {
    fail(message);
  }
}

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), '..', '..');
const preflightPath = path.join(repoRoot, 'scripts', 'dev_session_preflight.sh');
const packagePath = path.join(repoRoot, 'package.json');

assert(fs.existsSync(preflightPath), 'missing scripts/dev_session_preflight.sh');

try {
  fs.accessSync(preflightPath, fs.constants.X_OK);
} catch {
  fail('scripts/dev_session_preflight.sh must be executable');
}

const expectedCommands = [
  'git fetch origin --prune',
  'git log --oneline --decorate origin/main',
  'gh issue list --state open',
  'gh pr list --state open',
];

const source = fs.readFileSync(preflightPath, 'utf8');
for (const expected of expectedCommands) {
  assert(
    source.includes(expected),
    `preflight script must include "${expected}"`,
  );
}

const forbiddenCommands = [
  'git reset --hard',
  'git clean -fd',
  'git checkout --',
];

for (const forbidden of forbiddenCommands) {
  assert(
    !source.includes(forbidden),
    `preflight script must stay read-only and must not include "${forbidden}"`,
  );
}

const packageJson = JSON.parse(fs.readFileSync(packagePath, 'utf8'));
const preflightScript = packageJson?.scripts?.['dev:preflight'];
assert(
  typeof preflightScript === 'string' && /\bscripts\/dev_session_preflight\.sh\b/.test(preflightScript),
  'package.json scripts.dev:preflight must invoke scripts/dev_session_preflight.sh',
);

console.log('[verify:dev-session-preflight] Preflight script contract checks passed.');
