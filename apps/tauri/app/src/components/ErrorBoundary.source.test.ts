import { describe, expect, it } from 'vitest';

type FsModule = { readFileSync: (path: string, encoding: string) => string };
type ProcessLike = { cwd: () => string };
type ModuleNS = { createRequire: (url: string) => (mod: string) => unknown };

const proc = (globalThis as unknown as { process: ProcessLike }).process;
const moduleNs = (await import(/* @vite-ignore */ 'node:module' as string)) as unknown as ModuleNS;
const req = moduleNs.createRequire(import.meta.url);
const fs = req('fs') as FsModule;
const sourcePath = `${proc.cwd()}/src/components/ErrorBoundary.tsx`;

describe('ErrorBoundary i18n contract', () => {
  it('localizes the dev detail summary label', () => {
    const source = fs.readFileSync(sourcePath, 'utf8');

    expect(source).toContain('error.devDetailSummary');
    expect(source).not.toContain('Error detail (dev only)');
  });

  it('routes client-report user agent access through the platform boundary', () => {
    const source = fs.readFileSync(sourcePath, 'utf8');

    expect(source).toContain('getRuntimeUserAgentSnippet');
    expect(source).not.toContain(['navigator', 'userAgent'].join('.'));
  });
});
