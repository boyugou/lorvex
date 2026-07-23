import { describe, expect, it } from 'vitest';

type FsModule = { readFileSync: (path: string, encoding: string) => string };
type ProcessLike = { cwd: () => string };
type ModuleNS = { createRequire: (url: string) => (mod: string) => unknown };

const proc = (globalThis as unknown as { process: ProcessLike }).process;
const moduleNs = (await import(/* @vite-ignore */ 'node:module' as string)) as unknown as ModuleNS;
const req = moduleNs.createRequire(import.meta.url);
const fs = req('fs') as FsModule;

describe('EventForm color swatch radio contract', () => {
  it('uses radio state and shared roving keyboard wiring for color swatches', () => {
    const source = fs.readFileSync(`${proc.cwd()}/src/components/calendar/event-form/EventForm.tsx`, 'utf8');

    expect(source).toContain('handleRovingRadioGroupKeyDown({');
    expect(source).toContain('handleRovingRadioSpaceKey({');
    expect(source).toContain('role="radio"');
    expect(source).toContain('aria-checked={selected}');
    expect(source).toContain('tabIndex={selected ? 0 : -1}');
    expect(source).not.toContain('aria-pressed={selected}');
  });
});
