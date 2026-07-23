#!/usr/bin/env node
// Tailwind class audit — catches the project-specific footguns documented
// in CLAUDE.md → "Common Pitfalls".
//
// Why a custom script instead of `eslint-plugin-tailwindcss`?
//   * The v3 line scans `tailwind.config.{js,ts}`, which Lorvex does not
//     have (Tailwind 4 uses CSS `@theme`). It falls back to a slow
//     heuristic that takes >2 minutes on this tree.
//   * The v4 line is still alpha (4.0.0-alpha.2) at the time of writing.
//   * We only need to catch a handful of concrete footguns, not a full
//     class validator — a focused grep is faster, more reliable, and
//     easier to extend.
//
// Footguns enforced:
//   1. `border-border`        — invalid; project uses `border-surface-N`.
//   2. `text-text-text`       — accidental double prefix.
//   3. `bg-background`        — non-existent token.
//   4. `bg-${...}` /
//      `text-${...}` /
//      `border-${...}`        — Tailwind cannot generate dynamic class
//                               names; they break in production builds.
//   5. `rounded-{md,lg,xl,2xl}` /
//      `shadow-{xs,sm,md,lg,xl,2xl}`
//                              — raw Tailwind size buckets bypass the
//                               canonical `--radius-r-*` / `--shadow-*`
//                               tokens declared in `app/src/index.css`
//                               `@theme`. Tracked under #3398 / #3410.
//                               Phase-1 swept ui/settings/today-view/
//                               task-card/task-detail/task-list-view.
//                               Phase-2 swept calendar/
//                               dependency-graph/quick-capture/
//                               weekly-review/sidebar/
//                               command-palette. Phase-3 (#3438) swept
//                               every remaining subtree under
//                               app/src/components and app/src/app-shell.
//                               `raw-rounded` and `raw-shadow` are
//                               now HARD global errors. Phase-4
//                               (#3442) finished the final five
//                               raw-shadow sites and promoted the
//                               rule alongside raw-rounded. #4072
//                               added `shadow-xs` to the same raw
//                               shadow ban after AppSelect exposed
//                               the gap.
//
// Most rules exit non-zero. The token-migration rules are hard errors
// in already-swept directories and warning-only (counted but never
// failing) elsewhere.

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = resolve(fileURLToPath(import.meta.url), '..', '..', '..');
const SCAN_ROOT = join(REPO_ROOT, 'app', 'src');

const FORBIDDEN = [
  {
    id: 'border-border',
    pattern: /\bborder-border\b/g,
    advice: 'Use `border-surface-1|2|3` (CLAUDE.md → Common Pitfalls).',
  },
  // Token-migration rules.
  // Both `raw-rounded` and `raw-shadow` are HARD errors EVERYWHERE
  // under app/src. Phase-3 (#3438) finished sweeping rounded; Phase-4
  // (#3442) finished the final five raw-shadow sites and promoted the
  // rule. Any new raw `rounded-{sm,md,lg,xl,2xl,3xl}` or
  // `shadow-{xs,sm,md,lg,xl,2xl}` anywhere in the tree is a regression.
  {
    id: 'raw-rounded',
    pattern: /\brounded(?:-(?:t|b|l|r|s|e|tl|tr|bl|br|ss|se|es|ee))?-(?:sm|md|lg|xl|2xl|3xl)\b/g,
    advice:
      'Use `rounded-[var(--radius-r-control|card|panel|modal|chip)]` from `@theme` in app/src/index.css (#3398/#3410/#3438).',
  },
  // Bare `rounded` is the Tailwind default (~4px) and bypasses the
  // canonical radius tokens just like the sized buckets above. Allowed
  // exceptions: `rounded-full`, `rounded-none`, `rounded-[...]` (arbitrary
  // value, typically `rounded-[var(--radius-r-*)]`). Phase-5 (#3446) swept
  // the remaining 51 sites and promoted this to a hard error.
  {
    id: 'raw-rounded-bare',
    // Bare `rounded` (~4px Tailwind default) bypasses the canonical
    // `--radius-r-*` tokens in `@theme`. Allowed exceptions live OUTSIDE
    // this regex: `rounded-full`, `rounded-none`, and arbitrary values
    // like `rounded-[var(--radius-r-card)]` — all those require a `-`
    // continuation, which the negative lookahead `(?![-\w])` excludes.
    // The lookbehind whitelists class-string delimiters (space, quote,
    // backtick) so JS identifiers like `const rounded = ...` don't match.
    // The post-match `skipInComment` filter further drops `// ... rounded`
    // prose-comment hits.
    pattern: /(?<=[ '"`])rounded(?=['"`]|\s*\$\{|\s+['"`]|\s+[a-z][\w-]+[-\s'"`/.:])/g,
    skipInComment: true,
    advice:
      'Bare `rounded` (~4px) bypasses radius tokens. Use `rounded-[var(--radius-r-control|card|panel|modal|chip)]` (#3446).',
  },
  {
    id: 'raw-shadow',
    pattern: /\bshadow-(?:xs|sm|md|lg|xl|2xl)\b/g,
    advice:
      'Use `shadow-[var(--shadow-tooltip|popover|modal)]` from `@theme` in app/src/index.css (#3398/#3442).',
  },
  {
    id: 'text-text-text',
    pattern: /\btext-text-text\b/g,
    advice: 'Likely a typo. Use `text-text-primary|secondary|muted`.',
  },
  {
    id: 'bg-background',
    pattern: /\bbg-background\b/g,
    advice: 'No such token. Use `bg-surface-0|1|2|3` or `bg-card`.',
  },
  // Dynamic Tailwind class strings — Tailwind 4 still scans source for
  // literal class names; interpolated bits never reach the JIT and silently
  // produce no CSS in production. CLAUDE.md → Common Pitfalls bans this.
  {
    id: 'dynamic-bg',
    pattern: /[`"']bg-\$\{/g,
    advice: 'Dynamic Tailwind classes do not work. Use a static lookup map.',
  },
  {
    id: 'dynamic-text',
    pattern: /[`"']text-\$\{/g,
    advice: 'Dynamic Tailwind classes do not work. Use a static lookup map.',
  },
  {
    id: 'dynamic-border',
    pattern: /[`"']border-\$\{/g,
    advice: 'Dynamic Tailwind classes do not work. Use a static lookup map.',
  },
];

const EXTS = new Set(['.ts', '.tsx', '.css']);
const SKIP_DIRS = new Set(['node_modules', 'dist', 'build', '.git']);

function* walk(dir) {
  for (const entry of readdirSync(dir)) {
    if (SKIP_DIRS.has(entry)) continue;
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) {
      yield* walk(full);
    } else if ([...EXTS].some((ext) => entry.endsWith(ext))) {
      yield full;
    }
  }
}

// Files that are allowed to mention raw classes (the token defs live
// here, and the audit script itself documents the patterns it forbids).
const SOFT_IGNORE_FILES = new Set([
  'app/src/index.css',
]);

// Directory prefixes that have been fully swept by Phase-1 (#3398) and
// Phase-2 (#3410). New raw `rounded-*` / `shadow-*` classes inside any
// of these subtrees are HARD errors so the freshly-migrated surface
// can never silently regress. Files outside these prefixes still emit
// soft warnings — Phase-3 will enumerate and migrate them.
const SWEPT_PREFIXES = [
  // Phase-1 (commit f74183703 — #3398)
  'app/src/components/ui/',
  'app/src/components/settings/',
  'app/src/components/today-view/',
  'app/src/components/task-card/',
  'app/src/components/task-detail/',
  'app/src/components/task-list-view/',
  // Phase-2 (#3410)
  'app/src/components/calendar/',
  'app/src/components/dependency-graph/',
  'app/src/components/quick-capture/',
  'app/src/components/weekly-review/',
  'app/src/components/sidebar/',
  'app/src/components/command-palette/',
];

function isSwept(rel) {
  // Normalize to forward slashes so the prefix check works on Windows.
  const norm = rel.replaceAll('\\', '/');
  return SWEPT_PREFIXES.some((p) => norm.startsWith(p));
}

const violations = [];
const warnings = [];

for (const file of walk(SCAN_ROOT)) {
  let src;
  try {
    src = readFileSync(file, 'utf8');
  } catch {
    continue;
  }
  const rel = relative(REPO_ROOT, file);
  for (const rule of FORBIDDEN) {
    rule.pattern.lastIndex = 0;
    let match;
    while ((match = rule.pattern.exec(src)) !== null) {
      const line = src.slice(0, match.index).split('\n').length;
      if (rule.skipInComment) {
        // Skip matches inside JS comments on the same physical line:
        //   * `// ... rounded ...` (line comment)
        //   * ` * ... rounded ...` (JSDoc / block-comment continuation)
        // Tailwind classes only live inside string/template literals, not
        // prose, so this filter is safe and removes the only realistic
        // false-positive class for the bare-`rounded` rule.
        const lineStart = src.lastIndexOf('\n', match.index - 1) + 1;
        const before = src.slice(lineStart, match.index);
        if (before.includes('//')) continue;
        if (/^\s*\*(?!\/)/.test(before)) continue;
      }
      const entry = { file: rel, line, id: rule.id, advice: rule.advice, snippet: match[0] };
      if (rule.soft) {
        if (SOFT_IGNORE_FILES.has(rel)) continue;
        warnings.push(entry);
      } else if (rule.softUnlessSwept) {
        if (SOFT_IGNORE_FILES.has(rel)) continue;
        if (isSwept(rel)) {
          violations.push(entry);
        } else {
          warnings.push(entry);
        }
      } else {
        if (SOFT_IGNORE_FILES.has(rel)) continue;
        violations.push(entry);
      }
    }
  }
}

if (warnings.length > 0) {
  console.warn(`tailwind_class_audit: ${warnings.length} warning(s) [soft, non-blocking]:\n`);
  for (const v of warnings) {
    console.warn(`  ${v.file}:${v.line}  [${v.id}]  ${v.snippet}`);
    console.warn(`    -> ${v.advice}`);
  }
  console.warn('');
}

if (violations.length === 0) {
  console.log(`tailwind_class_audit: 0 hard violations across ${SCAN_ROOT} (${warnings.length} soft warnings)`);
  process.exit(0);
}

console.error(`tailwind_class_audit: ${violations.length} hard violation(s):\n`);
for (const v of violations) {
  console.error(`  ${v.file}:${v.line}  [${v.id}]  ${v.snippet}`);
  console.error(`    -> ${v.advice}`);
}
process.exit(1);
