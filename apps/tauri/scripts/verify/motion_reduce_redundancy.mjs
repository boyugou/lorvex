#!/usr/bin/env node
/**
 * Guard against redundant `motion-reduce:` Tailwind utilities creeping
 * back into the frontend.
 *
 * The global `@media (prefers-reduced-motion: reduce)` rule in
 * `app/src/styles/accessibility.css` (#3563) clamps every `transition-duration` and
 * `animation-duration` to 0.01ms via the universal selector, and the
 * follow-on rule (#3577) explicitly suppresses every shadowed
 * `.animate-*` class with `animation: none !important`. Together those
 * make the per-site `motion-reduce:transition-none` and
 * `motion-reduce:animate-none` utilities entirely redundant.
 *
 * Walk/match/report machinery is delegated to the shared
 * `_forbidden_pattern.mjs` helper (#3625).
 *
 * Exemptions (#3582): the existing call sites listed below legitimately
 * mention these tokens inside comment text that documents the contract.
 * The exemption list is intentionally an exact `(file, line)` set — if
 * a cited line is moved or deleted, the gate must be updated too.
 *
 * #3639: per-rule exemption Sets (matches focus_ring_consistency.mjs).
 * Sharing one Set across both rules concealed which rule a given
 * (file, line) is allowed to violate — a `transition-none` exemption
 * silently authorized an `animate-none` violation at the same site.
 */
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { runForbiddenPatternGate } from './_forbidden_pattern.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');

runForbiddenPatternGate({
  gateId: 'motion_reduce_redundancy',
  scanRoot: path.join(repoRoot, 'app', 'src'),
  repoRoot,
  okMessage:
    '[motion_reduce_redundancy] OK — no redundant motion-reduce:* utilities in app/src.',
  patterns: [
    {
      id: 'transitionNone',
      label: 'motion-reduce:transition-none (redundant — #3563 clamps transitions globally)',
      pattern: 'motion-reduce:transition-none',
      suggestion:
        'Remove — the #3563 global `* { transition-duration: 0.01ms !important }` already handles this.',
      exemptions: new Map([
        // Doc-comment in the accessibility stylesheet describing the redundant token contract.
        // #3791 — sentinel-pinned so doc-comment edits above this line
        // do not require a "refresh exemption pins" bookkeeping commit.
        ['app/src/styles/accessibility.css:@motion-reduce-transition-doc', 'doc-comment naming the redundant utility (#3582)'],
        // RevealButton inline comment documenting why the utility is
        // not used at the call site.
        ['app/src/components/ui/RevealButton.tsx:156', 'inline justification for not using motion-reduce:transition-none (#3582)'],
      ]),
    },
    {
      id: 'animateNone',
      label: 'motion-reduce:animate-none (redundant — #3577 suppresses every .animate-* class globally)',
      pattern: 'motion-reduce:animate-none',
      suggestion:
        'Remove — the #3577 global `animation: none !important` on every shadowed animation class already handles this.',
      exemptions: new Map([
        ['app/src/styles/accessibility.css:@motion-reduce-animate-doc', 'doc-comment naming the redundant utility (#3582)'],
      ]),
    },
  ],
});
