import { describe, expect, it } from 'vitest';

type FsNS = { readFileSync: (path: string, encoding: 'utf8') => string };
const fs = (await import(/* @vite-ignore */ 'node:fs' as string)) as unknown as FsNS;

describe('TaskCard logical list accent', () => {
  it('uses inline-start border properties instead of physical left borders', () => {
    const source = fs.readFileSync('src/components/task-card/TaskCard.tsx', 'utf8');

    expect(source).toContain('borderInlineStartColor: listInfo.color');
    expect(source).toContain("borderInlineStartWidth: '3px'");
    expect(source).not.toContain('borderLeftColor');
    expect(source).not.toContain('borderLeftWidth');
  });
});
