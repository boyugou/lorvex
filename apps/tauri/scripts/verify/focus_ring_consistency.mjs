#!/usr/bin/env node
/**
 * Guard against hand-rolled `focus-visible:ring-* focus-visible:ring-accent*`
 * utilities creeping back into the frontend, and against accent-button
 * misuse of the soft focus ring.
 *
 * The canonical focus affordances are the `focus-ring-soft` /
 * `focus-ring-strong` utilities defined in `app/src/styles/utilities.css` (#3603).
 * Hand-rolling the underlying ring/outline classes drifts in subtle ways
 * (different opacity, missing `outline-hidden`, ring color picked up
 * `--color-card` instead of `--color-accent`) and bypasses the WCAG
 * 2.4.7 / 1.4.11 non-text-contrast tuning the utilities encode.
 *
 * The 367-site mechanical sweep landed in #3615; the prominent-control
 * sweep landed in #3618. The current canonical usage count is ~388
 * `focus-ring-soft|focus-ring-strong` references across `app/src` (#3620).
 *
 * Forbidden patterns (each gated separately):
 *
 *   1. `bareRing` — `focus-visible:ring-[12]` followed within a bounded
 *      class-composition window by `focus-visible:ring-accent|success|danger|warning`.
 *      Use `focus-ring-soft` (compact controls) or `focus-ring-strong`
 *      (prominent controls).
 *
 *   2. `bareFocusRing` — `focus:ring-1\s+focus:ring-accent(?:\/\d+)?`
 *      Non-`focus-visible` variants (legacy `focus:` only). Most should
 *      become `focus-ring-soft`; visibility-on-focus is what we want.
 *
 *   3. `bgAccentSoft` — a className string that contains both
 *      `bg-accent` (solid, NOT `bg-accent/<n>`) and `focus-ring-soft`.
 *      Solid accent buttons need the surface-0 halo from
 *      `focus-ring-strong` to remain legible against busy backgrounds.
 *      `bg-accent/<n>` (faded) is allowed — soft is fine.
 *
 * Exemptions are an exact `(file, line)` allowlist — if the cited line
 * moves, the list must move with it. Brittle by design.
 *
 * Walk/match/report machinery is delegated to the shared
 * `_forbidden_pattern.mjs` helper (#3625).
 */
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { runForbiddenPatternGate } from './_forbidden_pattern.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

runForbiddenPatternGate({
  gateId: 'focus_ring_consistency',
  scanRoot: path.join(repoRoot, 'app', 'src'),
  repoRoot,
  okMessage:
    '[focus_ring_consistency] OK — no hand-rolled focus-ring patterns or accent-button policy violations in app/src.',
  patterns: [
    {
      id: 'bareRing',
      label: 'bare focus-visible:ring-[12] focus-visible:ring-{accent|success|danger|warning}',
      // #3688 — widened to also catch hand-rolled semantic-tone rings
      // (`focus-visible:ring-success/60`, etc.) so they migrate to the
      // new `focus-ring-soft-{success,danger,warning}` utilities.
      // #4072 — multiline mode catches split-array composition such as:
      //   'focus-visible:ring-2',
      //   'focus-visible:ring-accent/40',
      // while the 240-character cap keeps the match inside one local
      // class recipe instead of spanning unrelated controls.
      pattern: /focus-visible:ring-(?:1|2)\b[\s\S]{0,240}?focus-visible:ring-(?:accent|success|danger|warning)(?:\/\d+)?/,
      multiline: true,
      suggestion:
        'Use `focus-ring-soft` / `focus-ring-strong` (accent) or `focus-ring-soft-{success,danger,warning}` for semantic tones. See app/src/styles/utilities.css.',
      exemptions: new Set([
        // Doc-comment in the utilities stylesheet describing the *previous* hand-rolled
        // pattern that motivated `focus-ring-soft`/`focus-ring-strong`.
        // #3791 — sentinel-pinned to survive doc-comment edits.
        'app/src/styles/utilities.css:@focus-ring-doc',
        // Regression test that asserts the canonical RevealButton no longer ships the bare class.
        'app/src/components/ui/revealButtonHit.logic.test.ts:139',
      ]),
    },
    {
      id: 'bareFocusRing',
      label: 'bare focus:ring-1 focus:ring-accent (non-focus-visible)',
      pattern: /focus:ring-1\s+focus:ring-accent(?:\/\d+)?/,
      suggestion:
        'Use `focus-ring-soft` (visibility on focus-visible is what we want, not on every focus).',
      exemptions: new Set(),
    },
    {
      id: 'bgAccentSoft',
      label: 'bg-accent paired with focus-ring-soft',
      // Match a single quoted className-like string that contains BOTH a
      // solid `bg-accent` (not `bg-accent/<n>`) and `focus-ring-soft`.
      // Limit lookahead window to ~400 chars to avoid catastrophic backtracking.
      pattern: /\bbg-accent(?![/\w-])(?=[^"'`]{0,400}\bfocus-ring-soft\b)|\bfocus-ring-soft\b(?=[^"'`]{0,400}\bbg-accent(?![/\w-]))/,
      suggestion:
        'Solid bg-accent buttons should pair with `focus-ring-strong` for surface-0 halo separation.',
      exemptions: new Set([
        // Conditional `bg-accent` on a small (5x5) selectable checkbox; soft is correct.
        // #3804 — sentinel-pinned via the `@verify-exempt-next` form
        // (#3808) so future edits above the className don't drift the
        // pin. The marker sits on the preceding comment line.
        'app/src/components/ui/SelectableTaskCard.tsx:@selectable-task-card-bg-accent',
      ]),
    },
  ],
});
