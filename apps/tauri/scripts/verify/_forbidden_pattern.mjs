/**
 * Shared scanner machinery for "forbidden pattern" verify gates (#3625).
 *
 * Several gates (focus_ring_consistency, motion_reduce_redundancy, and
 * others) all share the same structural skeleton:
 *   - walk a directory tree, skipping common build dirs
 *   - filter to a fixed set of file extensions
 *   - scan each file's text against one or more forbidden patterns
 *   - allow exact (file, line) exemptions per pattern
 *   - exit 1 on any violation, with grouped reporting
 *
 * Each gate previously open-coded that skeleton, which drifted (different
 * exemption shapes, different reporting). This module owns the canonical
 * implementation; gates declare their patterns + exemptions and delegate
 * the walk/match/report.
 *
 * Exemption keys (#3791): three forms are accepted.
 *   - Line-pinned:   `app/src/index.css:2991`
 *     The literal 1-based line number. Brittle: any insertion above
 *     the cited line breaks the pin and a fresh "refresh exemption
 *     pins" commit is required. Useful only when the surrounding
 *     code is genuinely stable.
 *   - Sentinel-pinned: `app/src/index.css:@motion-reduce-doc`
 *     The line is located at scan time by searching the file for a
 *     `/* @verify-exempt: <name> *\/` marker comment on the exempt
 *     line itself. The marker moves with the code, so refactors and
 *     line-number drift no longer invalidate the gate. If the cited
 *     sentinel cannot be found in the file, the gate fails loud
 *     (typo / deleted comment surface immediately rather than
 *     silently allowing every line in that file).
 *   - Sentinel-pinned (next-line, #3808):
 *     `app/src/foo.tsx:@selectable-task-card-bg-accent`, where the
 *     marker form is `/* @verify-exempt-next: <name> *\/`. Resolves
 *     to the line *immediately after* the marker. Use this when the
 *     forbidden token lives on a JSX/expression line where you
 *     cannot embed an inline comment without breaking parser layout
 *     (e.g. a `className` template literal); place the comment on
 *     the preceding line instead.
 *
 * Marker syntax (#3807): the marker must appear inside a comment —
 * a literal `@verify-exempt:` token in a string is NOT honored. The
 * scanner enforces this by requiring the line content before the
 * marker to begin with a comment opener (`//`, `/*`, `*` continuation
 * inside a block comment, or `#`).
 *
 * Prefer sentinel form for any exemption that lives in a long-lived
 * source file likely to be edited above the pinned line.
 *
 * @typedef {Object} ForbiddenPattern
 * @property {string} id — short stable identifier used in violation reports
 * @property {string} label — human-readable description of the rule
 * @property {RegExp | string} pattern — regex (preferred) or literal substring
 * @property {string=} suggestion — actionable fix hint surfaced on violation
 * @property {Set<string> | Map<string, string>=} exemptions —
 *           `${relPath}:${lineNo}` allowlist. `Set<string>` keeps the
 *           legacy "just an allowlist" shape; `Map<string, string>`
 *           (#3641) carries a per-entry rationale that is printed on
 *           violation so reviewers see *why* a site was once exempted
 *           rather than reverse-engineering it from git blame.
 * @property {boolean=} multiline — when true, the gate tests `pattern`
 *           against the full file contents instead of one line at a
 *           time, then reports the first line that contains a match
 *           inside the matched span. Required for cross-line patterns
 *           (e.g. an opening `<style>` followed by a forbidden
 *           declaration on the next line).
 *
 * @typedef {Object} GateConfig
 * @property {string} gateId — name of the gate (used in log prefix)
 * @property {string} scanRoot — absolute path to the directory tree to scan
 * @property {string} repoRoot — absolute path used for path.relative()
 * @property {ForbiddenPattern[]} patterns
 * @property {Set<string>=} skipDirs — defaults to common build dirs
 * @property {Set<string>=} extensions — defaults to JS/TS/CSS source files
 * @property {string=} okMessage — success log; default mentions gateId
 */

import fs from 'node:fs';
import path from 'node:path';

const DEFAULT_SKIP_DIRS = new Set(['node_modules', 'dist', 'build', '.next', '.turbo']);
const DEFAULT_EXTENSIONS = new Set(['.ts', '.tsx', '.js', '.jsx', '.css', '.mjs']);

// #3806 — marker regex hoisted to module scope so the same compiled
// instance is reused across every file scan. The pattern is stateless
// per-line (we read `m[1]` from each `exec()` call) so a single shared
// instance is safe; we still reset `lastIndex` defensively before each
// scan because `g` flag carries state across calls. The two markers
// each get their own regex so name capture groups stay simple.
const SENTINEL_RE = /@verify-exempt:\s*([A-Za-z0-9_-]+)/g;
const SENTINEL_NEXT_RE = /@verify-exempt-next:\s*([A-Za-z0-9_-]+)/g;
// #3807 — comment-context guard. The marker must appear inside a
// comment, not in an arbitrary string literal — so the line content
// preceding the marker must look like a comment opener. We accept:
//   `//`  — JS/TS/Rust line comment
//   `/*`  — JS/TS/CSS block-comment opener
//   ` *`  — block-comment continuation line
//   `#`   — shell / Python / TOML line comment
//   `--`  — SQL line comment (a few SQL files live in scripts/)
// Leading whitespace allowed. Anything else (e.g. a string literal
// `"@verify-exempt: foo"`) is rejected, so a stray match in code
// can't silently exempt a line.
const COMMENT_PREFIX_RE = /^[\s]*(?:\/\/|\/\*|\*|#|--)/;

/**
 * Run a forbidden-pattern gate. Exits the process on violations (so each
 * gate file can stay a one-liner). Returns nothing — log + exit semantics
 * are owned here.
 *
 * @param {GateConfig} config
 */
export function runForbiddenPatternGate(config) {
  const {
    gateId,
    scanRoot,
    repoRoot,
    patterns,
    skipDirs = DEFAULT_SKIP_DIRS,
    extensions = DEFAULT_EXTENSIONS,
    okMessage,
  } = config;

  /** @type {{ ruleId: string; file: string; line: number; text: string }[]} */
  const violations = [];

  /** @param {string} dir */
  function walk(dir) {
    const entries = fs.readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.name.startsWith('.')) continue;
      if (skipDirs.has(entry.name)) continue;
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(full);
        continue;
      }
      if (!entry.isFile()) continue;
      const ext = path.extname(entry.name);
      if (!extensions.has(ext)) continue;
      const text = fs.readFileSync(full, 'utf8');
      const rel = path.relative(repoRoot, full);
      const lines = text.split('\n');
      // #3791 / #3808: build sentinel maps once per file. Two maps so
      // resolution stays O(1) per match check and the two semantics
      // (exempt-this-line vs. exempt-next-line) cannot drift.
      // #3823 — `buildSentinelMaps` throws on duplicate-sentinel
      // FATAL; translate to an exit-code-1 termination here so the
      // gate stays a one-liner for callers and the pure helper stays
      // unit-testable via `assert.throws`.
      let sentinelMap;
      let sentinelNextMap;
      try {
        ({ sentinelMap, sentinelNextMap } = buildSentinelMaps(lines, rel));
      } catch (error) {
        console.error(error instanceof Error ? error.message : String(error));
        process.exit(1);
      }
      // #3805: precompute the (rule × file) exempt-line set so the
      // hot path is `exemptLines.has(lineNo)` instead of an O(N)
      // scan of the exemption key list per match. Each rule still
      // owns its own exemptions; the precompute happens per rule
      // per file inside the loop below.
      for (const rule of patterns) {
        if (!testPattern(rule.pattern, text)) continue;
        const exemptLines = buildExemptLineSet(
          rule.exemptions,
          rel,
          sentinelMap,
          sentinelNextMap,
        );
        if (rule.multiline) {
          // Multiline mode (#3641): the rule's `pattern` is tested
          // against the full file contents. Find the first line whose
          // 0-based index lies inside the matched span and report it.
          const matchInfo = findMultilineMatch(rule.pattern, text);
          if (!matchInfo) continue;
          const lineNo = matchInfo.line;
          if (exemptLines.has(lineNo)) continue;
          violations.push({
            ruleId: rule.id,
            file: rel,
            line: lineNo,
            text: lines[lineNo - 1]?.trim() ?? '',
          });
          continue;
        }
        lines.forEach((line, idx) => {
          const lineNo = idx + 1;
          if (!testPattern(rule.pattern, line)) return;
          if (exemptLines.has(lineNo)) return;
          violations.push({ ruleId: rule.id, file: rel, line: lineNo, text: line.trim() });
        });
      }
    }
  }

  walk(scanRoot);

  if (violations.length > 0) {
    console.error(`[${gateId}] ERROR: ${violations.length} policy violation(s) found.`);
    const byRule = new Map();
    for (const v of violations) {
      if (!byRule.has(v.ruleId)) byRule.set(v.ruleId, []);
      byRule.get(v.ruleId).push(v);
    }
    for (const rule of patterns) {
      const items = byRule.get(rule.id);
      if (!items?.length) continue;
      console.error(`\n  [${rule.id}] ${rule.label} — ${items.length} occurrence(s)`);
      if (rule.suggestion) console.error(`    ${rule.suggestion}`);
      for (const v of items) {
        console.error(`    ${v.file}:${v.line}  ${v.text}`);
      }
    }
    // #3641: surface every exemption rationale at the bottom of the
    // report so reviewers see exactly what tradeoff each existing
    // exempted site is opting out of, even when only a different site
    // is currently violating.
    const rationales = collectExemptionRationales(patterns);
    if (rationales.length > 0) {
      console.error('\n  Active exemptions (rationale):');
      for (const { ruleId, key, reason } of rationales) {
        console.error(`    [${ruleId}] ${key} — ${reason}`);
      }
    }
    process.exit(1);
  }

  console.log(okMessage ?? `[${gateId}] OK — no violations found.`);
}

/**
 * Build the precomputed `Set<lineNo>` of exempt 1-based line numbers
 * for `(rule, file)`. Combines literal line-pinned keys and both
 * sentinel-pinned forms (`@verify-exempt`, this-line; `@verify-exempt-next`,
 * next-line). #3805 — fast path is now `exemptLines.has(lineNo)`,
 * O(1) per candidate violation; previously each candidate scanned the
 * entire exemption key set looking for `path:@name` shapes.
 *
 * If a sentinel exemption references a name that does not appear in
 * the corresponding map, the gate exits 1 — silent allowlist drift is
 * unacceptable.
 *
 * @param {Set<string> | Map<string, string> | undefined} exemptions
 * @param {string} rel — repo-relative file path
 * @param {Map<string, number>} sentinelMap — `@verify-exempt` (this-line)
 * @param {Map<string, number>} sentinelNextMap — `@verify-exempt-next`
 */
function buildExemptLineSet(exemptions, rel, sentinelMap, sentinelNextMap) {
  /** @type {Set<number>} */
  const exemptLines = new Set();
  if (!exemptions) return exemptLines;
  const prefix = `${rel}:`;
  for (const key of exemptions.keys()) {
    if (typeof key !== 'string') continue;
    if (!key.startsWith(prefix)) continue;
    const suffix = key.slice(prefix.length);
    if (suffix.startsWith('@')) {
      const name = suffix.slice(1);
      // Two-map lookup: a sentinel name may live in either map, but
      // not both (`buildSentinelMaps` enforces uniqueness across both
      // maps). Try the this-line map first because it's the more
      // common form.
      const thisLine = sentinelMap.get(name);
      if (thisLine !== undefined) {
        exemptLines.add(thisLine);
        continue;
      }
      const nextLine = sentinelNextMap.get(name);
      if (nextLine !== undefined) {
        exemptLines.add(nextLine);
        continue;
      }
      console.error(
        `[forbidden_pattern] FATAL: sentinel @${name} not found in ${rel}. ` +
          `Add a \`/* @verify-exempt: ${name} */\` (this-line) or ` +
          `\`/* @verify-exempt-next: ${name} */\` (preceding-line) comment, ` +
          `or remove the stale exemption.`,
      );
      process.exit(1);
    } else {
      const lineNo = Number(suffix);
      if (Number.isFinite(lineNo)) exemptLines.add(lineNo);
    }
  }
  return exemptLines;
}

/**
 * Build per-file maps for both sentinel forms (#3791, #3808):
 *   - `sentinelMap`: `@verify-exempt: <name>` → marker's own 1-based line
 *   - `sentinelNextMap`: `@verify-exempt-next: <name>` → line *after* marker
 *
 * Markers must appear inside a comment (#3807); a literal occurrence
 * inside a string is rejected by `COMMENT_PREFIX_RE`. Duplicate
 * sentinel names anywhere across either map within a single file fail
 * loud — otherwise two exemption keys could resolve to the same name
 * and the gate would silently honor the first hit.
 *
 * @param {string[]} lines
 * @param {string} rel — used for diagnostics on duplicate / non-comment markers
 */
export function buildSentinelMaps(lines, rel) {
  /** @type {Map<string, number>} */
  const sentinelMap = new Map();
  /** @type {Map<string, number>} */
  const sentinelNextMap = new Map();
  /**
   * #3823 — throw rather than `process.exit(1)` so the function stays
   * test-friendly. `runForbiddenPatternGate` is the gate-level entry
   * point that owns exit-code translation; `buildSentinelMaps` is a
   * pure function that should propagate failures via exceptions so
   * unit tests can `assert.throws` without forking a subprocess.
   *
   * @param {string} name @param {number} otherLine @param {number} thisLine
   */
  const failDuplicate = (name, otherLine, thisLine) => {
    throw new Error(
      `[forbidden_pattern] FATAL: duplicate sentinel @${name} on lines ${otherLine} and ${thisLine} in ${rel}.`,
    );
  };
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (!line.includes('@verify-exempt')) continue;
    // #3807 — reject string-literal markers. The comment prefix check
    // anchors to the start of the line (modulo whitespace), which is
    // correct for `//`, `#`, ` *` continuation, `/*` openers and SQL
    // `--`. Embedded comments (e.g. mid-expression `/* ... */`) are
    // intentionally rejected here: marker comments should sit on
    // their own line so reviewers can see the exemption rationale at
    // a glance.
    if (!COMMENT_PREFIX_RE.test(line)) continue;
    SENTINEL_RE.lastIndex = 0;
    /** @type {RegExpExecArray | null} */
    let m;
    while ((m = SENTINEL_RE.exec(line)) !== null) {
      const name = m[1];
      const existingThis = sentinelMap.get(name);
      if (existingThis !== undefined) failDuplicate(name, existingThis, i + 1);
      const existingNext = sentinelNextMap.get(name);
      if (existingNext !== undefined) failDuplicate(name, existingNext, i + 1);
      sentinelMap.set(name, i + 1);
    }
    SENTINEL_NEXT_RE.lastIndex = 0;
    while ((m = SENTINEL_NEXT_RE.exec(line)) !== null) {
      const name = m[1];
      const existingThis = sentinelMap.get(name);
      if (existingThis !== undefined) failDuplicate(name, existingThis, i + 1);
      const existingNext = sentinelNextMap.get(name);
      if (existingNext !== undefined) failDuplicate(name, existingNext, i + 1);
      // Resolve to the *next* line. If the marker sits on the file's
      // final line there is nothing to exempt; we still record `i + 2`
      // so the buildExemptLineSet caller produces a no-op rather than
      // a fatal — a stale marker without a target line below it will
      // surface as the missing-sentinel error instead.
      sentinelNextMap.set(name, i + 2);
    }
  }
  return { sentinelMap, sentinelNextMap };
}

/**
 * Walk every rule's exemptions and return only the Map-shaped entries
 * (which carry rationale strings). Set-shaped exemptions return empty.
 *
 * @param {ForbiddenPattern[]} patterns
 */
function collectExemptionRationales(patterns) {
  /** @type {{ ruleId: string; key: string; reason: string }[]} */
  const out = [];
  for (const rule of patterns) {
    if (!(rule.exemptions instanceof Map)) continue;
    for (const [key, reason] of rule.exemptions) {
      out.push({ ruleId: rule.id, key, reason });
    }
  }
  return out;
}

/**
 * Locate the first matched span in `text` and return the 1-based line
 * number it starts on. Used by multiline gates to report a useful
 * file:line anchor even when the matched pattern straddles a newline.
 *
 * @param {RegExp | string} pattern
 * @param {string} text
 */
function findMultilineMatch(pattern, text) {
  let index;
  if (typeof pattern === 'string') {
    index = text.indexOf(pattern);
    if (index < 0) return null;
  } else {
    if (pattern.global || pattern.sticky) pattern.lastIndex = 0;
    const match = pattern.exec(text);
    if (!match) return null;
    index = match.index;
  }
  // 1-based line number = number of newlines before `index` + 1.
  let line = 1;
  for (let i = 0; i < index; i++) {
    if (text.charCodeAt(i) === 10 /* \n */) line++;
  }
  return { line };
}

/** @param {RegExp | string} pattern @param {string} subject */
function testPattern(pattern, subject) {
  if (typeof pattern === 'string') return subject.includes(pattern);
  // Reset stateful flags for global regexes.
  if (pattern.global || pattern.sticky) pattern.lastIndex = 0;
  return pattern.test(subject);
}
