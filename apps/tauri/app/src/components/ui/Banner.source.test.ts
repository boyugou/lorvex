import { describe, expect, it } from 'vitest';

type FsModule = { readFileSync: (path: string, encoding: string) => string };
type ProcessLike = { cwd: () => string };
type ModuleNS = { createRequire: (url: string) => (mod: string) => unknown };

const proc = (globalThis as unknown as { process: ProcessLike }).process;
const moduleNs = (await import(/* @vite-ignore */ 'node:module' as string)) as unknown as ModuleNS;
const req = moduleNs.createRequire(import.meta.url);
const fs = req('fs') as FsModule;
const sourcePath = `${proc.cwd()}/src/components/ui/Banner.tsx`;

describe('Banner density contract', () => {
  it('does not keep the unused compact density in the Banner primitive', () => {
    const source = fs.readFileSync(sourcePath, 'utf8');

    expect(source).not.toMatch(/type BannerDensity = [^\n]*compact/);
    expect(source).not.toContain("compact: 'py-2'");
    expect(source).not.toMatch(/density = 'compact'/);
  });
});
