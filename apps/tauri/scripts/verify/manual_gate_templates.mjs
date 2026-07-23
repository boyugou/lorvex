#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  COMMON_PLACEHOLDERS,
  EXPECTED_DOC_REFERENCES,
  TEMPLATE_SPECS,
} from '../manual-gate/templates.mjs';

const REQUIRED_EVIDENCE_PERMALINK_FIELD = '- Evidence permalink:';
const REQUIRED_EVIDENCE_TARGET_FIELD = '- Evidence target:';
const HISTORICAL_MANUAL_GATE_TARGET_RE =
  /(?:--issue\s+(?:168|169|170)\b|issue-(?:168|169|170)\.md|issue\s+#(?:168|169|170)\b|\(#(?:168|169|170)\))/i;

function fail(message) {
  console.error(`[manual_gate_templates] ERROR: ${message}`);
  process.exit(1);
}

function toPosix(relativePath) {
  return relativePath.split(path.sep).join('/');
}

function renderForCheck(templateContent) {
  return templateContent.replace(/\{\{([A-Z_]+)\}\}/g, (match, token) => {
    if (token === 'DATE') return '2026-03-04';
    if (token === 'EVIDENCE_TARGET') return 'issue #999';
    if (token === 'EVIDENCE_TARGET_SLUG') return 'issue-999';
    if (token === 'COMMIT') return 'abcdef0';
    if (token === 'CAPTURED_AT_UTC') return '2026-03-04T00:00:00Z';
    if (token === 'FRESH_UNTIL_UTC') return '2026-03-18T00:00:00Z';
    fail(`Unknown placeholder ${match}`);
  });
}

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), '..', '..');

for (const [templateId, spec] of Object.entries(TEMPLATE_SPECS)) {
  const templateAbsolutePath = path.join(repoRoot, spec.templatePath);
  if (!fs.existsSync(templateAbsolutePath)) {
    fail(`Missing template file for "${templateId}": ${spec.templatePath}`);
  }

  const templateContent = fs.readFileSync(templateAbsolutePath, 'utf8');
  if (!templateContent.includes(REQUIRED_EVIDENCE_PERMALINK_FIELD)) {
    fail(`${spec.templatePath} missing required evidence permalink field: ${REQUIRED_EVIDENCE_PERMALINK_FIELD}`);
  }
  if (!templateContent.includes(REQUIRED_EVIDENCE_TARGET_FIELD)) {
    fail(`${spec.templatePath} missing required explicit evidence target field: ${REQUIRED_EVIDENCE_TARGET_FIELD}`);
  }

  for (const placeholder of COMMON_PLACEHOLDERS) {
    if (!templateContent.includes(placeholder)) {
      fail(`${spec.templatePath} missing required placeholder: ${placeholder}`);
    }
  }

  for (const heading of spec.requiredHeadings) {
    if (!templateContent.includes(heading)) {
      fail(`${spec.templatePath} missing required heading: ${heading}`);
    }
  }

  const rendered = renderForCheck(templateContent);
  if (/\{\{[A-Z_]+\}\}/.test(rendered)) {
    fail(`${spec.templatePath} leaves unresolved placeholders after sample render`);
  }
  if (!rendered.includes(REQUIRED_EVIDENCE_PERMALINK_FIELD)) {
    fail(`${spec.templatePath} sample render omitted required evidence permalink field`);
  }
  if (!rendered.includes('- Evidence target: issue #999')) {
    fail(`${spec.templatePath} sample render omitted concrete evidence target field`);
  }

  console.log(
    `[manual_gate_templates] OK: ${templateId} template (${toPosix(spec.templatePath)})`,
  );
}

for (const rule of EXPECTED_DOC_REFERENCES) {
  const docAbsolutePath = path.join(repoRoot, rule.docPath);
  if (!fs.existsSync(docAbsolutePath)) {
    fail(`Missing documentation file: ${rule.docPath}`);
  }

  const docContent = fs.readFileSync(docAbsolutePath, 'utf8');
  if (HISTORICAL_MANUAL_GATE_TARGET_RE.test(docContent)) {
    fail(`${rule.docPath} routes manual-gate evidence to a historical closed issue target`);
  }
  const missingSnippets = rule.requiredSnippets.filter((snippet) => !docContent.includes(snippet));
  if (missingSnippets.length > 0) {
    fail(`${rule.docPath} missing required snippet(s): ${missingSnippets.join(' | ')}`);
  }

  console.log(`[manual_gate_templates] OK: references present in ${rule.docPath}`);
}

console.log(
  `[manual_gate_templates] OK: verified ${Object.keys(TEMPLATE_SPECS).length} template(s) and ${EXPECTED_DOC_REFERENCES.length} documentation reference rule(s).`,
);
