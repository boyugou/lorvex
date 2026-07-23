#!/usr/bin/env node
/**
 * Issue #3412: knip unused-export budget gate.
 *
 * `knip` (https://knip.dev) reports unused exports / exported types in
 * the React frontend (`app/`). This verifier runs knip from the repo
 * root with the `app` workspace selected so root-level runtime/contract
 * tests are part of the import graph. That lets the budget stay at zero:
 * exports used only by those tests are counted as live, and genuinely
 * dead frontend API surface fails the gate.
 *
 * Thresholds live in `scripts/verify/knip_unused.config.json` so they
 * can be ratcheted down without touching this script.
 *
 * The script intentionally skips locally when the local knip binary
 * can't be invoked (e.g. dependency-less checkout), but fails closed in
 * GitHub Actions where `npm ci` is expected to have installed the pinned
 * project dependency.
 */
import path from 'node:path';
import fs from 'node:fs';
import { spawnSync } from 'node:child_process';

import { resolveRepoRootFromMeta, runVerifierCli } from '../lib/verifier_runtime.mjs';

const SCRIPT_TAG = '[knip_unused]';
const REPO_ROOT = resolveRepoRootFromMeta(import.meta.url);
const CONFIG_PATH = path.join(REPO_ROOT, 'scripts', 'verify', 'knip_unused.config.json');
const DEFAULT_KNIP_BIN = path.join(
  REPO_ROOT,
  'node_modules',
  '.bin',
  process.platform === 'win32' ? 'knip.cmd' : 'knip',
);
const KNIP_BIN = process.env.KNIP_UNUSED_BIN || DEFAULT_KNIP_BIN;
const KNIP_REPORT_SECTION_RE = /^(?:Unused|Unlisted|Unresolved|Configuration) .*\(\d+\)$/m;
const ANSI_ESCAPE_RE = /\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])/g;

function loadThresholds() {
  const raw = fs.readFileSync(CONFIG_PATH, 'utf8');
  const parsed = JSON.parse(raw);
  if (typeof parsed.maxUnusedExports !== 'number') {
    throw new Error(`${SCRIPT_TAG} config missing numeric maxUnusedExports`);
  }
  if (typeof parsed.maxUnusedExportedTypes !== 'number') {
    throw new Error(`${SCRIPT_TAG} config missing numeric maxUnusedExportedTypes`);
  }
  return {
    maxUnusedExports: parsed.maxUnusedExports,
    maxUnusedExportedTypes: parsed.maxUnusedExportedTypes,
  };
}

function knipChildEnv() {
  const env = { ...process.env };
  // The bundle runner sets FORCE_COLOR=1 for prefixed live output. Knip
  // is parsed as machine output here, so keep its child process plain.
  delete env.FORCE_COLOR;
  return env;
}

function runKnip() {
  const knipProbe = spawnSync(KNIP_BIN, ['--version'], {
    env: knipChildEnv(),
    stdio: 'ignore',
  });
  if (knipProbe.status !== 0) {
    if (process.env.GITHUB_ACTIONS === 'true') {
      throw new Error(
        `${SCRIPT_TAG} Knip is required in GitHub Actions; expected executable at ${KNIP_BIN}. ` +
          'Run npm ci before verify:ci-typecheck and keep the pinned knip devDependency installed.',
      );
    }
    console.warn(`${SCRIPT_TAG} local knip binary not available; skipping knip budget gate.`);
    return null;
  }

  const result = spawnSync(
    KNIP_BIN,
    ['--workspace', 'app', '--no-progress', '--no-config-hints', '--no-exit-code'],
    {
      cwd: REPO_ROOT,
      encoding: 'utf8',
      env: knipChildEnv(),
      // Knip emits its findings on stdout. Errors (vite-config load
      // failures etc.) hit stderr but don't change the symbol counts.
      stdio: ['ignore', 'pipe', 'pipe'],
    },
  );

  if (result.error) {
    throw new Error(
      `${SCRIPT_TAG} failed to invoke knip: ${result.error.message}`,
    );
  }
  if (result.status !== 0 || result.signal) {
    const detail = [
      `status=${result.status ?? 'null'}`,
      `signal=${result.signal ?? 'null'}`,
      result.stdout ? `stdout:\n${result.stdout.trim()}` : '',
      result.stderr ? `stderr:\n${result.stderr.trim()}` : '',
    ].filter(Boolean).join('\n');
    throw new Error(`${SCRIPT_TAG} knip process failed.\n${detail}`);
  }

  return `${result.stdout ?? ''}\n${result.stderr ?? ''}`;
}

/**
 * Parse knip's symbol reporter output. Each issue section starts with a
 * header like:
 *
 *     Unused exports (119)
 *     foo  function  src/...
 *     bar  type      src/...
 *     Unused exported types (55)
 *     ...
 *
 * We extract the `(N)` count from the section header — the symbol rows
 * underneath are advisory listings, not the source of truth.
 */
function parseCounts(output) {
  const normalizedOutput = output.replace(ANSI_ESCAPE_RE, '');
  const exportsMatch = normalizedOutput.match(/^Unused exports \((\d+)\)/m);
  const typesMatch = normalizedOutput.match(/^Unused exported types \((\d+)\)/m);
  if (!exportsMatch && !typesMatch && normalizedOutput.trim() && !KNIP_REPORT_SECTION_RE.test(normalizedOutput)) {
    throw new Error(
      `${SCRIPT_TAG} unparseable knip output; expected knip report section headers.\n` +
        normalizedOutput.trim(),
    );
  }
  const unusedExports = exportsMatch ? Number(exportsMatch[1]) : 0;
  const unusedExportedTypes = typesMatch ? Number(typesMatch[1]) : 0;
  return { unusedExports, unusedExportedTypes };
}

function extractSection(output, headerPattern) {
  const lines = output.replace(ANSI_ESCAPE_RE, '').split('\n');
  const startIdx = lines.findIndex((line) => headerPattern.test(line));
  if (startIdx === -1) return [];
  const collected = [];
  for (let i = startIdx + 1; i < lines.length; i += 1) {
    const line = lines[i];
    if (/^Unused /.test(line) || /^Unlisted /.test(line) || /^Configuration /.test(line) || line.trim() === '') {
      // Trimmed-empty lines are tolerated mid-section (knip can emit
      // them between domains); the next "Unused …" header marks end.
      if (/^Unused /.test(line) || /^Unlisted /.test(line) || /^Configuration /.test(line)) break;
      continue;
    }
    collected.push(line);
  }
  return collected;
}

function run() {
  const output = runKnip();
  if (output === null) return;

  const { unusedExports, unusedExportedTypes } = parseCounts(output);
  const { maxUnusedExports, maxUnusedExportedTypes } = loadThresholds();

  const breaches = [];
  if (unusedExports > maxUnusedExports) {
    const section = extractSection(output, /^Unused exports \(/);
    breaches.push(
      `Unused exports: ${unusedExports} > budget ${maxUnusedExports}\n` +
        section.map((l) => `  ${l}`).join('\n'),
    );
  }
  if (unusedExportedTypes > maxUnusedExportedTypes) {
    const section = extractSection(output, /^Unused exported types \(/);
    breaches.push(
      `Unused exported types: ${unusedExportedTypes} > budget ${maxUnusedExportedTypes}\n` +
        section.map((l) => `  ${l}`).join('\n'),
    );
  }

  if (breaches.length > 0) {
    throw new Error(
      `${SCRIPT_TAG} knip budget exceeded.\n` +
        breaches.join('\n\n') +
        '\n\nEither delete / demote the unused symbol(s), or — if the new ' +
        'export is deliberate — adjust the budget in ' +
        'scripts/verify/knip_unused.config.json with a justification.',
    );
  }

  console.log(
    `${SCRIPT_TAG} knip budget clean: ${unusedExports} unused exports ` +
      `(<= ${maxUnusedExports}), ${unusedExportedTypes} unused exported types ` +
      `(<= ${maxUnusedExportedTypes}).`,
  );
}

runVerifierCli({
  scriptTag: SCRIPT_TAG,
  run,
});
