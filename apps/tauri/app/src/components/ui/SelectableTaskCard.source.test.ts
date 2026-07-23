import { describe, expect, it } from 'vitest';

type FsNS = { readFileSync: (path: string, encoding: 'utf8') => string };
const fs = (await import(/* @vite-ignore */ 'node:fs' as string)) as unknown as FsNS;

describe('SelectableTaskCard accessibility contract', () => {
  it('routes checkbox semantics through the task row button instead of rendering a second button', () => {
    const source = fs.readFileSync('src/components/ui/SelectableTaskCard.tsx', 'utf8');

    expect(source).not.toContain('<button');
    expect(source).toContain('aria-hidden="true"');
    expect(source).toContain('taskButtonRole="checkbox"');
    expect(source).toContain('taskButtonAriaChecked={selected}');
    expect(source).toContain('taskButtonAriaLabel={selectionLabel}');
    expect(source).toContain('taskButtonDisabled={bulkBusy}');
    expect(source).toContain('hideQuickActions');
  });
});
