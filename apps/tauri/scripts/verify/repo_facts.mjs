#!/usr/bin/env node
/**
 * Audit #2984-DC-H1: lint canonical user-facing docs against the generated
 * MCP tool count from `docs/reference/REPO_FACTS.md`.
 *
 * `scripts/generate/repo_facts.mjs --check` (npm run verify:repo-facts)
 * already guarantees `docs/reference/REPO_FACTS.md` is fresh. But that
 * guarantee never reached human-facing docs (README, ROADMAP, SKILL.md):
 * pre-fix README shipped THREE different MCP tool counts on a single
 * release. This verifier closes the loop — it parses the canonical count
 * from the generated facts file and asserts every numeric "N MCP tools"
 * / "N-tool" / "Rust, N tools" mention in those canonical docs uses the
 * same number.
 *
 * Drift is rejected with a precise file:line:matched-text report so
 * regenerating the docs becomes mechanical.
 *
 * CLI:
 *   node scripts/verify/repo_facts.mjs           → exit 0 if clean
 *   node scripts/verify/repo_facts.mjs --check   → alias for default
 */
import fs from 'node:fs';
import path from 'node:path';

import { resolveRepoRootFromMeta, runVerifierCli } from '../lib/verifier_runtime.mjs';

const SCRIPT_TAG = '[verify:repo-facts-prose]';
const REPO_ROOT = resolveRepoRootFromMeta(import.meta.url);

const FACTS_REL = 'docs/reference/REPO_FACTS.md';

/**
 * Files that carry user-facing prose about the MCP tool count. If a new
 * surface starts quoting the count, add it here.
 */
const CANONICAL_DOCS = ['README.md', 'ROADMAP.md', 'skill/SKILL.md'];

/**
 * Patterns that quote the MCP tool count. Each match group captures the
 * numeric value. Patterns are deliberately narrow — generic phrases like
 * "120 tools" without an MCP qualifier could legitimately refer to other
 * counts and would false-flag.
 */
const TOOL_COUNT_PATTERNS = [
  /(\d{2,4})\s+MCP\s+tools?\b/gi,
  /(\d{2,4})-tool\s+MCP\s+server/gi,
  /MCP\s+server[^.\n]*\((\d{2,4})\s+tools?\)/gi,
  /MCP\s+server[^.\n]*\(\s*all\s+(\d{2,4})\s+tools?\s*\)/gi,
  /\bRust,\s+(\d{2,4})\s+tools?\b/gi,
];

function parseCanonicalToolCount(factsBody) {
  const match = factsBody.match(/Total MCP tools:\s*\*\*(\d+)\*\*/);
  if (!match) {
    throw new Error(
      `${SCRIPT_TAG} could not parse "Total MCP tools" from ${FACTS_REL}. ` +
        `Has the format changed? Inspect docs/reference/REPO_FACTS.md.`,
    );
  }
  return Number(match[1]);
}

function findDriftInDoc(absolutePath, relativePath, canonicalCount) {
  const body = fs.readFileSync(absolutePath, 'utf8');
  const lines = body.split('\n');
  const drift = [];
  for (const pattern of TOOL_COUNT_PATTERNS) {
    pattern.lastIndex = 0;
    let m;
    while ((m = pattern.exec(body)) !== null) {
      const value = Number(m[1]);
      if (value === canonicalCount) continue;
      const upTo = body.slice(0, m.index);
      const lineNumber = upTo.split('\n').length;
      const line = lines[lineNumber - 1] ?? '';
      drift.push({
        file: relativePath,
        line: lineNumber,
        value,
        snippet: line.trim(),
      });
    }
  }
  return drift;
}

function run() {
  const factsPath = path.join(REPO_ROOT, FACTS_REL);
  if (!fs.existsSync(factsPath)) {
    throw new Error(`${SCRIPT_TAG} missing facts file: ${FACTS_REL}`);
  }
  const factsBody = fs.readFileSync(factsPath, 'utf8');
  const canonicalCount = parseCanonicalToolCount(factsBody);

  const drift = [];
  for (const rel of CANONICAL_DOCS) {
    const abs = path.join(REPO_ROOT, rel);
    if (!fs.existsSync(abs)) {
      throw new Error(`${SCRIPT_TAG} missing canonical doc: ${rel}`);
    }
    drift.push(...findDriftInDoc(abs, rel, canonicalCount));
  }

  if (drift.length > 0) {
    const lines = drift.map(
      (d) =>
        `  ${d.file}:${d.line} → quotes ${d.value} (canonical: ${canonicalCount})\n     ${d.snippet}`,
    );
    throw new Error(
      `${SCRIPT_TAG} MCP tool count drift detected — fix the prose to match ${FACTS_REL}:\n` +
        lines.join('\n'),
    );
  }

  console.log(
    `${SCRIPT_TAG} canonical count = ${canonicalCount}; ${CANONICAL_DOCS.length} doc(s) clean.`,
  );
}

runVerifierCli({
  scriptTag: SCRIPT_TAG,
  successMessage: 'MCP tool count prose matches docs/reference/REPO_FACTS.md.',
  run,
});
