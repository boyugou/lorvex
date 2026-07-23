import { describe, expect, it } from 'vitest';

type FsNS = { readFileSync: (path: string, encoding: 'utf8') => string };
const fs = (await import(/* @vite-ignore */ 'node:fs' as string)) as unknown as FsNS;

describe('task metadata tag chips', () => {
  it('bounds long tag labels without hiding the full value from assistive metadata', () => {
    const source = fs.readFileSync('src/components/task-detail/metadata-editor/primitives.tsx', 'utf8');

    expect(source).toContain('title={tag}');
    expect(source).toContain('max-w-full min-w-0');
    expect(source).toContain('className="select-text-content min-w-0 truncate"');
  });
});
