import { describe, expect, it } from 'vitest';

type FsNS = { readFileSync: (path: string, encoding: 'utf8') => string };
const fs = (await import(/* @vite-ignore */ 'node:fs' as string)) as unknown as FsNS;

describe('NavItem tooltip direction wiring', () => {
  it('derives tooltip side from locale direction instead of a fixed physical side', () => {
    const source = fs.readFileSync('src/components/sidebar/NavItem.tsx', 'utf8');

    expect(source).toContain('localeTextDirection(locale)');
    expect(source).toContain('navItemTooltipSideForDirection(');
    expect(source).toContain('side={tooltipSide}');
    expect(source).not.toContain('side="right"');
  });
});
