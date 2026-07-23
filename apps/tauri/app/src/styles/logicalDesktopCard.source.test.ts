import { describe, expect, it } from 'vitest';

type FsNS = { readFileSync: (path: string, encoding: 'utf8') => string };
const fs = (await import(/* @vite-ignore */ 'node:fs' as string)) as unknown as FsNS;

describe('desktop-card logical shell edge', () => {
  it('uses inline-end shell border tokens instead of physical right-edge tokens', () => {
    const utilities = fs.readFileSync('src/styles/utilities.css', 'utf8');
    const themes = fs.readFileSync('src/styles/themes.css', 'utf8');
    const tokens = fs.readFileSync('../docs/design/DESIGN_TOKENS.md', 'utf8');
    const combined = `${utilities}\n${themes}\n${tokens}`;

    expect(utilities).toContain('border-inline-end: var(--shell-card-border-inline-end');
    expect(themes).toContain('--shell-card-border-inline-end: 1px solid var(--shell-card-border-color);');
    expect(tokens).toContain('`--shell-card-border-inline-end`');
    expect(utilities).not.toContain('border-right:');
    expect(combined).not.toContain('--shell-card-border-right');
    expect(combined).not.toContain('border-right: var(--shell-card-border-right');
  });
});
