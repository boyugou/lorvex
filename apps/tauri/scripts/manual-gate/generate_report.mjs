#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  MANUAL_GATE_FRESHNESS_DAYS,
  MANUAL_GATE_OUTPUT_DIR,
  TEMPLATE_SPECS,
  resolveManualGateOutputRoot,
} from './templates.mjs';

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const ISSUE_RE = /^\d+$/;
const RELEASE_TARGET_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,119}$/;

function fail(message) {
  console.error(`[manual_gate_report] ERROR: ${message}`);
  process.exit(1);
}

function usage() {
  console.log(`Usage:
  npm run docs:manual-gate:report -- --template <id> --date YYYY-MM-DD (--issue N | --pr N | --release-target ID) [--commit SHA] [--out PATH] [--overwrite]

Template ids:
  ${Object.keys(TEMPLATE_SPECS).join(', ')}

Default output:
  ${MANUAL_GATE_OUTPUT_DIR}/<template>/YYYY-MM-DD/<target-slug>.md
`);
}

function parseArgs(argv) {
  const args = {};
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === '--help' || token === '-h') {
      args.help = true;
      continue;
    }
    if (token === '--overwrite') {
      args.overwrite = true;
      continue;
    }
    if (!token.startsWith('--')) {
      fail(`Unexpected argument: ${token}`);
    }
    const key = token.slice(2);
    const value = argv[index + 1];
    if (!value || value.startsWith('--')) {
      fail(`Missing value for ${token}`);
    }
    args[key] = value;
    index += 1;
  }
  return args;
}

function toPosix(relativePath) {
  return relativePath.split(path.sep).join('/');
}

function toIsoNoMillis(value) {
  return value.toISOString().replace('.000Z', 'Z');
}

function displayOutputPath(absolutePath) {
  const relativePath = path.relative(repoRoot, absolutePath);
  if (relativePath && !relativePath.startsWith('..') && !path.isAbsolute(relativePath)) {
    return toPosix(relativePath);
  }
  return toPosix(absolutePath);
}

function computeCapturedAtUtc(date) {
  return `${date}T00:00:00Z`;
}

function computeFreshUntilUtc(date, days) {
  const parsed = new Date(`${date}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime())) {
    fail(`Unable to parse --date for freshness computation: ${date}`);
  }
  parsed.setUTCDate(parsed.getUTCDate() + days);
  return toIsoNoMillis(parsed);
}

function isPlaceholder(value) {
  return !value
    || value.includes('{{')
    || value.includes('}}')
    || /^<[^>]+>$/.test(value)
    || (value.includes('<') && value.includes('>'));
}

function resolveEvidenceTarget(args) {
  const suppliedTargets = [
    ['--issue', args.issue],
    ['--pr', args.pr],
    ['--release-target', args['release-target']],
  ].filter(([, value]) => value !== undefined);

  if (suppliedTargets.length !== 1) {
    fail('Missing evidence target; pass exactly one of --issue N, --pr N, or --release-target <release-target>');
  }

  const [flag, value] = suppliedTargets[0];
  if (isPlaceholder(value)) {
    fail(`${flag} must be a concrete current evidence target, got placeholder: ${value}`);
  }

  if (flag === '--issue') {
    if (!ISSUE_RE.test(value)) {
      fail(`Invalid --issue value: ${value}`);
    }
    return {
      display: `issue #${value}`,
      slug: `issue-${value}`,
    };
  }

  if (flag === '--pr') {
    if (!ISSUE_RE.test(value)) {
      fail(`Invalid --pr value: ${value}`);
    }
    return {
      display: `PR #${value}`,
      slug: `pr-${value}`,
    };
  }

  if (!RELEASE_TARGET_RE.test(value)) {
    fail(`Invalid --release-target value: ${value}`);
  }
  return {
    display: `release ${value}`,
    slug: `release-${value}`,
  };
}

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), '..', '..');
const args = parseArgs(process.argv.slice(2));

if (args.help) {
  usage();
  process.exit(0);
}

const templateId = args.template;
if (!templateId) {
  usage();
  fail('Missing required --template argument');
}

const templateSpec = TEMPLATE_SPECS[templateId];
if (!templateSpec) {
  fail(`Unknown template id: ${templateId}`);
}

const date = args.date;
if (!date || !DATE_RE.test(date)) {
  fail('Missing or invalid --date (expected YYYY-MM-DD)');
}

const evidenceTarget = resolveEvidenceTarget(args);
const commit = args.commit ?? '<fill-commit-sha>';
const capturedAtUtc = computeCapturedAtUtc(date);
const freshUntilUtc = computeFreshUntilUtc(date, MANUAL_GATE_FRESHNESS_DAYS);
const templateAbsolutePath = path.join(repoRoot, templateSpec.templatePath);
if (!fs.existsSync(templateAbsolutePath)) {
  fail(`Template file not found: ${templateSpec.templatePath}`);
}

const templateContent = fs.readFileSync(templateAbsolutePath, 'utf8');
const rendered = templateContent.replace(/\{\{([A-Z_]+)\}\}/g, (match, token) => {
  if (token === 'DATE') return date;
  if (token === 'EVIDENCE_TARGET') return evidenceTarget.display;
  if (token === 'EVIDENCE_TARGET_SLUG') return evidenceTarget.slug;
  if (token === 'COMMIT') return commit;
  if (token === 'CAPTURED_AT_UTC') return capturedAtUtc;
  if (token === 'FRESH_UNTIL_UTC') return freshUntilUtc;
  fail(`Unknown placeholder ${match} in ${templateSpec.templatePath}`);
});

if (/\{\{[A-Z_]+\}\}/.test(rendered)) {
  fail(`Unresolved placeholder(s) remain in rendered output for template ${templateId}`);
}

const outputAbsolutePath = args.out
  ? path.resolve(repoRoot, toPosix(args.out))
  : path.join(resolveManualGateOutputRoot(repoRoot), templateSpec.outputSlug, date, `${evidenceTarget.slug}.md`);

if (args.out && outputAbsolutePath !== repoRoot && !outputAbsolutePath.startsWith(`${repoRoot}${path.sep}`)) {
  fail('Output path must remain inside this repository');
}

if (fs.existsSync(outputAbsolutePath) && !args.overwrite) {
  fail(`Output already exists: ${displayOutputPath(outputAbsolutePath)}`);
}

fs.mkdirSync(path.dirname(outputAbsolutePath), { recursive: true });
fs.writeFileSync(
  outputAbsolutePath,
  rendered.endsWith('\n') ? rendered : `${rendered}\n`,
  'utf8',
);

console.log(`[manual_gate_report] Template: ${templateId}`);
console.log(`[manual_gate_report] Output: ${displayOutputPath(outputAbsolutePath)}`);
