/**
 * #3524 / #3531 regression: the WCAG 2.5.8 24×24 hit-target on the tag-X
 * button is implemented as a `::before` overlay. Pre-#3524 it lived on the
 * button itself with `overflow: hidden` (which clipped the overlay back to
 * the button's 14×14 box). Pre-#3531 the overlay was sized off the button's
 * box via `inset: -5px`, which made the hit target shrink during the
 * reveal animation as the button's own width animated. The current shape:
 *
 *   - `.tag-x-button` is the un-clipped frame (no overflow:hidden)
 *   - `.tag-x-button::before` is a CONSTANT 24×24 box centred on the
 *     button — invariant to the reveal animation
 *   - `.tag-x-glyph` (inner wrapper) owns the width 0↔0.875rem reveal
 *
 * #3532: this file used to assert CSS only. A reverted JSX wrapper
 * (i.e. removing the `<span class="tag-x-glyph">` around the icon)
 * would have left every CSS assertion green. We now also assert the
 * primitives.tsx source contains the wrapper structurally so a JSX
 * regression cannot slip past the CSS gate.
 */
import { describe, expect, it } from 'vitest';

import { readCssImportGraph } from '@/test-support/cssGraph';

// Read the CSS via the Node `fs` module that's available in vitest's Node
// test environment. We pull it through `globalThis` rather than `import` so
// the `app` tsconfig (which deliberately omits `@types/node` to keep
// frontend code from depending on Node globals) doesn't need to change.
type FsModule = { readFileSync: (path: string, encoding: string) => string };
type ProcessLike = { cwd: () => string };
type ModuleNS = { createRequire: (url: string) => (mod: string) => unknown };

const proc = (globalThis as unknown as { process: ProcessLike }).process;
// `app` tsconfig omits `@types/node` deliberately, so `node:module` cannot
// be statically imported. Resolve it through the dynamic `import()` form
// the bundler can't see (`/* @vite-ignore */`) — at runtime under vitest's
// Node environment this returns the real `module` builtin.
const moduleNs = (await import(/* @vite-ignore */ 'node:module' as string)) as unknown as ModuleNS;
const req = moduleNs.createRequire(import.meta.url);
const fs = req('fs') as FsModule;
const cssPath = `${proc.cwd()}/src/index.css`;
const css = readCssImportGraph(fs, cssPath);
const primitivesSrc = fs.readFileSync(
  `${proc.cwd()}/src/components/task-detail/metadata-editor/primitives.tsx`,
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

describe('#3524 / #3531 tag-X hit target (24×24 WCAG 2.5.8)', () => {
  it('declares an `::before` hit-target overlay sized to a constant 24×24', () => {
    // #3561: geometry was hoisted into a shared
    // `:where(.tag-x-button, .reveal-button-hit)::before` base rule so
    // the chip-X and the generic reveal-button primitive stay in
    // lockstep. Assert the geometry on the shared rule.
    const sharedBlock = blockFor(':where(.tag-x-button, .reveal-button-hit)::before {');
    expect(sharedBlock).toMatch(/width:\s*24px/);
    expect(sharedBlock).toMatch(/height:\s*24px/);
    expect(sharedBlock).toMatch(/left:\s*50%/);
    expect(sharedBlock).toMatch(/top:\s*50%/);
    expect(sharedBlock).toMatch(/transform:\s*translate\(-50%,\s*-50%\)/);
    // `inset: -5px` is the stale, animating-box-relative sizing — must NOT
    // come back.
    expect(sharedBlock).not.toMatch(/inset:\s*-5px/);
    // The per-primitive arm carries the `content: none` baseline.
    const tagXBlock = blockFor('.tag-x-button::before {');
    expect(tagXBlock).toMatch(/content:\s*none/);
  });

  it('does not put `overflow: hidden` on `.tag-x-button` (would clip the overlay)', () => {
    const buttonBlock = blockFor('.tag-x-button {');
    expect(buttonBlock).not.toMatch(/overflow:\s*hidden/);
  });

  it('moves the visual reveal mask onto `.tag-x-glyph` (overflow:hidden + width animation)', () => {
    const glyphBlock = blockFor('.tag-x-glyph {');
    expect(glyphBlock).toMatch(/overflow:\s*hidden/);
    expect(glyphBlock).toMatch(/width:\s*0\b/);
    expect(glyphBlock).toMatch(/opacity:\s*0\b/);
  });

  it('reveals the glyph on hover / focus-within to width 0.875rem', () => {
    // #3546: dropped the dead `.tag-x-button:focus-visible .tag-x-glyph`
    // arm. The host chip carries `group/tag` and the X button is inside
    // it, so `.group/tag:focus-within` already covers keyboard focus on
    // the button — the third arm was a redundant duplicate that armed
    // the same state machine via a longer selector.
    expect(css).toMatch(
      /\.group\\\/tag:hover \.tag-x-glyph[\s\S]*?\.group\\\/tag:focus-within \.tag-x-glyph[\s\S]*?\{[\s\S]*?width:\s*0\.875rem/,
    );
    // The dead third arm must NOT come back.
    expect(css).not.toMatch(/\.tag-x-button:focus-visible \.tag-x-glyph\s*\{/);
  });

  it('keeps the touch-mode always-on reveal for `.tag-x-glyph`', () => {
    expect(css).toMatch(
      /@media \(hover: none\)[\s\S]*?\.tag-x-glyph[\s\S]*?width:\s*0\.875rem/,
    );
  });

  it('renders focus-visible outline on the overlay, not the button (#3541)', () => {
    // Outline lives on `.tag-x-button:focus-visible::before` so the ring
    // traces the stable 24×24 hit-target box rather than the animating
    // button's own (collapsing-width) frame.
    expect(css).toMatch(
      /\.tag-x-button:focus-visible::before[\s\S]*?outline:\s*2px solid var\(--color-accent\)/,
    );
    // The button itself must NOT carry the focus-visible outline utilities.
    expect(primitivesSrc).not.toMatch(/focus-visible:outline-2[\s\S]{0,40}outline-accent/);
  });

  it('JSX wrapper: <span class="tag-x-glyph"> contains the XIcon (#3532)', () => {
    // Structural assertion against `primitives.tsx` — without this gate,
    // reverting the wrapper (`.tag-x-glyph`) would leave every CSS-only
    // assertion green while breaking the actual reveal animation.
    expect(primitivesSrc).toMatch(/className="tag-x-glyph"/);
    // The XIcon must live inside the wrapper. Match the open tag, then any
    // attributes on the same span, then any whitespace, then the icon.
    expect(primitivesSrc).toMatch(
      /<span\s+className="tag-x-glyph"[^>]*>[\s\S]{0,400}<XIcon\b[\s\S]{0,200}<\/span>/,
    );
  });
});
