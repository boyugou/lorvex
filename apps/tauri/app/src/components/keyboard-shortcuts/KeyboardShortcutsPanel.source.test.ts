import { describe, expect, it } from 'vitest';

type FsModule = { readFileSync: (path: string, encoding: string) => string };
type ProcessLike = { cwd: () => string };
type ModuleNS = { createRequire: (url: string) => (mod: string) => unknown };

const proc = (globalThis as unknown as { process: ProcessLike }).process;
const moduleNs = (await import(/* @vite-ignore */ 'node:module' as string)) as unknown as ModuleNS;
const req = moduleNs.createRequire(import.meta.url);
const fs = req('fs') as FsModule;

function source(path: string): string {
  return fs.readFileSync(`${proc.cwd()}/${path}`, 'utf8');
}

describe('KeyboardShortcutsPanel move-in-view help text', () => {
  it('documents Kanban horizontal-only movement separately from Eisenhower vertical movement', () => {
    const sourceText = source('src/components/keyboard-shortcuts/KeyboardShortcutsPanel.tsx');

    expect(sourceText).not.toContain('${MOD}←→↑↓');
    expect(sourceText).toContain('${MOD}←→ (Kanban/Eisenhower) · ${MOD}↑↓ (Eisenhower)');
  });
});
