/**
 * #3553 / #3565 — `.reveal-button-hit` 24×24 hit-target overlay contract.
 *
 * Mirrors `tagXHitTarget.logic.test.ts` but for the generic reveal-button
 * primitive (`RevealButton` + `.reveal-button-hit` ::before overlay).
 *
 * Pre-#3553 the overlay was unconditionally materialised (`content: ''`
 * outside the `@media (hover: none)` arm), which produced two latent
 * defects:
 *
 *   1. INVISIBLE FOCUS — when the host button was at opacity 0 the
 *      overlay was still painted, so keyboard `:focus-visible` drew the
 *      outline on a phantom 24×24 box hovering over the row whitespace.
 *   2. CLICKABLE THROUGH WHITESPACE — the overlay carried
 *      `pointer-events: auto`, so collapsed-state buttons caught clicks
 *      anywhere inside the 24×24 frame even though the visible button
 *      was invisible.
 *
 * The current shape (mirrors `.tag-x-button::before`):
 *
 *   - Geometry (24×24 centred, transform-translate, border-radius) is
 *     factored into a shared `:where(.tag-x-button, .reveal-button-hit)`
 *     base rule (#3561).
 *   - `content: none` is the base, with three reveal-state arms flipping
 *     `content: ''`: `.group:hover`, `.group:focus-within`, and
 *     `:focus-visible` on the button itself.
 *   - `@media (hover: none)` arm flips `content: ''` always (touch).
 *   - The overlay carries `pointer-events: none`; the real hit area is
 *     the button itself, which has `min-width: 24px; min-height: 24px`
 *     so collapsed-state clicks don't bleed through (#3558).
 */
import { describe, expect, it } from 'vitest';

import { readCssImportGraph } from '@/test-support/cssGraph';

type FsModule = { readFileSync: (path: string, encoding: string) => string };
type ProcessLike = { cwd: () => string };
type ModuleNS = { createRequire: (url: string) => (mod: string) => unknown };

const proc = (globalThis as unknown as { process: ProcessLike }).process;
const moduleNs = (await import(/* @vite-ignore */ 'node:module' as string)) as unknown as ModuleNS;
const req = moduleNs.createRequire(import.meta.url);
const fs = req('fs') as FsModule;
const cssPath = `${proc.cwd()}/src/index.css`;
const css = readCssImportGraph(fs, cssPath);
const revealButtonSrc = fs.readFileSync(
  `${proc.cwd()}/src/components/ui/RevealButton.tsx`,
  'utf8',
);

/** Slice the CSS body for a single selector (terminated by the matching `}`). */
function blockFor(selector: string): string {
  const idx = css.indexOf(selector);
  if (idx === -1) throw new Error(`selector not found: ${selector}`);
  const open = css.indexOf('{', idx);
  const close = css.indexOf('}', open);
  return css.slice(open + 1, close);
}

describe('#3553 .reveal-button-hit hit-target (24×24 WCAG 2.5.8)', () => {
  it('shares the 24×24 geometry base rule with .tag-x-button (#3561)', () => {
    // Geometry lives on a shared `:where(...)` rule so the two primitives
    // stay in lockstep and we don't duplicate the constants.
    expect(css).toMatch(
      /:where\(\.tag-x-button,\s*\.reveal-button-hit\)::before\s*\{[\s\S]*?width:\s*24px[\s\S]*?height:\s*24px[\s\S]*?left:\s*50%[\s\S]*?top:\s*50%[\s\S]*?transform:\s*translate\(-50%,\s*-50%\)/,
    );
  });

  it('uses `content: none` baseline so the overlay is gated on reveal state (#3553)', () => {
    // Without `content: none`, the overlay is always materialised — even
    // when the host button is at opacity 0. That paints an invisible
    // focus outline and (with pointer-events: auto) catches stray clicks.
    const block = blockFor('.reveal-button-hit::before {');
    expect(block).toMatch(/content:\s*none/);
  });

  it('flips `content: \'\'` only on host hover / focus-within / button focus-visible', () => {
    // Three arms must materialise the overlay. Mirror the tag-X gating.
    expect(css).toMatch(
      /\.group:hover \.reveal-button-hit::before[\s\S]*?\.group:focus-within \.reveal-button-hit::before[\s\S]*?\.reveal-button-hit:focus-visible::before[\s\S]*?\{[\s\S]*?content:\s*''/,
    );
  });

  it('keeps the overlay always-on under `@media (hover: none)` (touch)', () => {
    expect(css).toMatch(
      /@media \(hover: none\)[\s\S]*?\.reveal-button-hit::before[\s\S]*?content:\s*''/,
    );
  });

  it('overlay is decorative — pointer-events: none + button carries the real 24×24 hit area (#3558)', () => {
    // The overlay must NOT extend the click region (clickable-through-
    // whitespace defect). The button itself enforces the 24×24 minimum
    // via min-width / min-height.
    const overlayBlock = blockFor('.reveal-button-hit::before {');
    expect(overlayBlock).toMatch(/pointer-events:\s*none/);
    const buttonBlock = blockFor('.reveal-button-hit {');
    expect(buttonBlock).toMatch(/min-width:\s*24px/);
    expect(buttonBlock).toMatch(/min-height:\s*24px/);
  });

  it('renders focus-visible outline on the overlay, not the button', () => {
    // Outline traces the stable 24×24 box rather than whatever inner
    // padding/font-size the call site happens to use. The button itself
    // suppresses its own outline via `outline: none`.
    expect(css).toMatch(
      /\.reveal-button-hit:focus-visible::before[\s\S]*?outline:\s*2px solid var\(--color-accent\)[\s\S]*?outline-offset:\s*1px/,
    );
    expect(css).toMatch(/\.reveal-button-hit:focus-visible\s*\{[\s\S]*?outline:\s*none/);
  });

  it('RevealButton applies `.reveal-button-hit` when hitTarget is true', () => {
    // The class is the contract — without it the CSS arms above don't
    // attach. Default is hitTarget=true.
    expect(revealButtonSrc).toMatch(/hitTarget\s*\?\s*'reveal-button-hit'\s*:\s*'reveal-button-no-hit'/);
    expect(revealButtonSrc).toMatch(/hitTarget\s*=\s*true/);
  });

  it('hitTarget=false intentionally does NOT carry the 24×24 floor (#3575)', () => {
    // `.reveal-button-no-hit` is the explicit escape hatch: callers that
    // already meet WCAG 2.5.8 by virtue of their own padding /
    // typography (e.g. TaskDetailHeader's monospace copy-id) opt out of
    // the shared min-width/min-height floor. Asserting the absence of
    // that rule keeps the contract honest — if someone later adds it
    // back the test will catch the silent over-reach.
    expect(css).not.toMatch(/\.reveal-button-no-hit\s*\{[^}]*min-width:\s*24px/);
    expect(css).not.toMatch(/\.reveal-button-no-hit\s*\{[^}]*min-height:\s*24px/);
  });

  it('hitTarget=false uses a direct outline rule on the button (#3559)', () => {
    // When the overlay is opted out, the focus ring lives directly
    // on the button via `.reveal-button-no-hit:focus-visible` —
    // matching the same `outline: 2px solid var(--color-accent);
    // outline-offset: 1px` contract as the overlay arm so both
    // variants land on the same visual.
    expect(css).toMatch(
      /\.reveal-button-no-hit:focus-visible\s*\{[\s\S]*?outline:\s*2px solid var\(--color-accent\)[\s\S]*?outline-offset:\s*1px/,
    );
    // The legacy Tailwind-ring fallback must NOT be present.
    expect(revealButtonSrc).not.toMatch(/focus-visible:ring-1\s+focus-visible:ring-accent\/60/);
  });
});
