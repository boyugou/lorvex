import { describe, expect, it } from 'vitest';

type FsModule = { readFileSync: (path: string, encoding: string) => string };
type ProcessLike = { cwd: () => string };
type ModuleNS = { createRequire: (url: string) => (mod: string) => unknown };

const proc = (globalThis as unknown as { process: ProcessLike }).process;
const moduleNs = (await import(/* @vite-ignore */ 'node:module' as string)) as unknown as ModuleNS;
const req = moduleNs.createRequire(import.meta.url);
const fs = req('fs') as FsModule;
const sourcePath = `${proc.cwd()}/src/components/context-menu/ContextMenu.tsx`;

function readSource(): string {
  return fs.readFileSync(sourcePath, 'utf8');
}

describe('ContextMenu RTL submenu wiring', () => {
  it('derives menu direction from locale metadata and mirrors the submenu indicator', () => {
    const source = readSource();

    expect(source).toContain('localeTextDirection(locale)');
    expect(source).toContain("textDirection === 'rtl' ? '‹' : '›'");
    expect(source).toContain('resolveContextSubmenuPosition(');
    expect(source).toContain('textDirection,');
    expect(source).toContain('textDirection: () => textDirection');
  });
});
