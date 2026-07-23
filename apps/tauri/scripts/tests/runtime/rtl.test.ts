import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';

// Source-level RTL guardrail.
//
// The UI sets `document.documentElement.dir = 'rtl'` for Arabic/Hebrew/Farsi/
// Urdu (see `app/src/lib/i18n.tsx`). For that to actually flip the layout,
// every horizontally-directional Tailwind utility in the app source must use
// a logical variant (`ms`, `me`, `ps`, `pe`, `start`, `end`,
// `rounded-s/e/ss/se/es/ee`, `border-s/e`, `text-start/end`) instead of the
// physical variant (`ml`, `mr`, `pl`, `pr`, `left`, `right`, `rounded-l/r/...`,
// `border-l/r`, `text-left/right`).
//
// This test scans every `.ts`/`.tsx` file under `app/src` and asserts that
// no physical class tokens survive. The token regex mirrors the one used
// by the migration sweep for issue #2132: it intentionally targets class
// values (numeric, Tailwind keyword, fraction, or arbitrary `[...]`) to
// avoid catching identical substrings that appear in prose (e.g. comments).

const APP_SRC = join(process.cwd(), 'app', 'src');

const NUMBER = '\\d+(?:\\.\\d+)?';
const FRACTION = '\\d+/\\d+';
const SPACING_KEYWORD = '(?:px|auto|full|none|screen|svh|dvh|lvh|min|max|fit|reverse)';
const ARBITRARY = '\\[[^\\]]+\\]';
const SPACING_VALUE = `(?:${NUMBER}|${FRACTION}|${SPACING_KEYWORD}|${ARBITRARY})`;
const ROUND_KEYWORD = '(?:none|sm|md|lg|xl|2xl|3xl|4xl|full)';
const ROUND_VALUE = `(?:${NUMBER}|${ROUND_KEYWORD}|${ARBITRARY})`;
const COLORY = '[A-Za-z]{2,}(?:-\\d+)?(?:/\\d+)?';
const BORDER_VALUE = `(?:${NUMBER}|${ROUND_KEYWORD}|${COLORY}|${ARBITRARY})`;

// Class-token boundary: char before must NOT be a class-internal identifier
// char, so we don't match `my-ml-2` as `ml-2` or substrings mid-word.
const PRE = '(?<![A-Za-z0-9/\\[\\]_\\-])';
const POST = '(?![A-Za-z0-9/\\[\\]_.\\-])';

const PHYSICAL_PATTERNS: ReadonlyArray<readonly [string, RegExp]> = [
  ['ml-', new RegExp(`${PRE}ml-${SPACING_VALUE}${POST}`)],
  ['mr-', new RegExp(`${PRE}mr-${SPACING_VALUE}${POST}`)],
  ['pl-', new RegExp(`${PRE}pl-${SPACING_VALUE}${POST}`)],
  ['pr-', new RegExp(`${PRE}pr-${SPACING_VALUE}${POST}`)],
  ['left-', new RegExp(`${PRE}left-${SPACING_VALUE}${POST}`)],
  ['right-', new RegExp(`${PRE}right-${SPACING_VALUE}${POST}`)],
  ['-ml-', new RegExp(`${PRE}-ml-${SPACING_VALUE}${POST}`)],
  ['-mr-', new RegExp(`${PRE}-mr-${SPACING_VALUE}${POST}`)],
  ['-left-', new RegExp(`${PRE}-left-${SPACING_VALUE}${POST}`)],
  ['-right-', new RegExp(`${PRE}-right-${SPACING_VALUE}${POST}`)],
  ['rounded-l-', new RegExp(`${PRE}rounded-l-${ROUND_VALUE}${POST}`)],
  ['rounded-r-', new RegExp(`${PRE}rounded-r-${ROUND_VALUE}${POST}`)],
  ['rounded-tl-', new RegExp(`${PRE}rounded-tl-${ROUND_VALUE}${POST}`)],
  ['rounded-tr-', new RegExp(`${PRE}rounded-tr-${ROUND_VALUE}${POST}`)],
  ['rounded-bl-', new RegExp(`${PRE}rounded-bl-${ROUND_VALUE}${POST}`)],
  ['rounded-br-', new RegExp(`${PRE}rounded-br-${ROUND_VALUE}${POST}`)],
  // Valueless rounded corner classes (e.g. `rounded-l`).
  ['rounded-l', new RegExp(`${PRE}rounded-l${POST}`)],
  ['rounded-r', new RegExp(`${PRE}rounded-r${POST}`)],
  ['rounded-tl', new RegExp(`${PRE}rounded-tl${POST}`)],
  ['rounded-tr', new RegExp(`${PRE}rounded-tr${POST}`)],
  ['rounded-bl', new RegExp(`${PRE}rounded-bl${POST}`)],
  ['rounded-br', new RegExp(`${PRE}rounded-br${POST}`)],
  ['border-l-', new RegExp(`${PRE}border-l-${BORDER_VALUE}${POST}`)],
  ['border-r-', new RegExp(`${PRE}border-r-${BORDER_VALUE}${POST}`)],
  ['border-l', new RegExp(`${PRE}border-l${POST}`)],
  ['border-r', new RegExp(`${PRE}border-r${POST}`)],
  ['text-left', new RegExp(`${PRE}text-left${POST}`)],
  ['text-right', new RegExp(`${PRE}text-right${POST}`)],
];

function* walk(dir: string): Generator<string> {
  for (const entry of readdirSync(dir)) {
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) {
      yield* walk(full);
    } else if (st.isFile() && (full.endsWith('.ts') || full.endsWith('.tsx'))) {
      yield full;
    }
  }
}

test('app/src is free of physical horizontal-direction Tailwind classes', () => {
  const violations: { file: string; token: string; lineNo: number; line: string }[] = [];
  for (const file of walk(APP_SRC)) {
    const body = readFileSync(file, 'utf8');
    const lines = body.split('\n');
    lines.forEach((line, i) => {
      // Skip JSX/TS line comments and block-comment bodies; a full AST walk is
      // overkill for the guardrail. The heuristic: lines that start (after
      // whitespace) with `//`, `*`, or that are inside `/* ... */` pairs are
      // prose. Block-comment tracking is lightweight — we just flag when
      // we're inside one.
      // (Handled via a running flag below.)
    });
    let inBlockComment = false;
    lines.forEach((rawLine, idx) => {
      let line = rawLine;
      // Strip // line comments (but leave JSX {/* … */} inline since they're
      // easier to handle via the block-comment flag).
      const trimmed = line.trim();
      if (trimmed.startsWith('//') || trimmed.startsWith('*')) return;
      // Strip block-comment content spanning this line.
      if (inBlockComment) {
        const end = line.indexOf('*/');
        if (end === -1) return;
        line = line.slice(end + 2);
        inBlockComment = false;
      }
      // Check for block-comment starts on this line.
      while (true) {
        const start = line.indexOf('/*');
        if (start === -1) break;
        const end = line.indexOf('*/', start + 2);
        if (end === -1) {
          line = line.slice(0, start);
          inBlockComment = true;
          break;
        }
        line = line.slice(0, start) + line.slice(end + 2);
      }
      // Strip JSX expression comments `{/* ... */}` that fit on one line.
      line = line.replace(/\{\s*\/\*[\s\S]*?\*\/\s*\}/g, '');
      for (const [token, re] of PHYSICAL_PATTERNS) {
        if (re.test(line)) {
          violations.push({ file, token, lineNo: idx + 1, line: rawLine.slice(0, 200) });
        }
      }
    });
  }
  assert.equal(
    violations.length,
    0,
    `Physical horizontal Tailwind classes found in app/src:\n${violations
      .slice(0, 20)
      .map((v) => `  ${v.file}:${v.lineNo} [${v.token}] ${v.line.trim()}`)
      .join('\n')}`,
  );
});

test('app/src no longer carries unresolved RTL TODO debt from issue #2132', () => {
  const offenders: string[] = [];
  for (const file of walk(APP_SRC)) {
    const body = readFileSync(file, 'utf8');
    if (body.includes('TODO(#2132)')) {
      offenders.push(file);
    }
  }

  assert.equal(
    offenders.length,
    0,
    `Unresolved RTL TODO(#2132) comments remain in:\n${offenders.join('\n')}`,
  );
});
