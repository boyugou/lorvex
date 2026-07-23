import { describe, expect, it } from 'vitest';

type FsModule = { readFileSync: (path: string, encoding: string) => string };
type ProcessLike = { cwd: () => string };
type ModuleNS = { createRequire: (url: string) => (mod: string) => unknown };

const proc = (globalThis as unknown as { process: ProcessLike }).process;
const moduleNs = (await import(/* @vite-ignore */ 'node:module' as string)) as unknown as ModuleNS;
const req = moduleNs.createRequire(import.meta.url);
const fs = req('fs') as FsModule;
const sourcePath = `${proc.cwd()}/src/components/calendar/MonthGrid/DesktopMonthGrid.tsx`;

describe('DesktopMonthGrid accessibility structure', () => {
  it('keeps task and event buttons out of button-like month cell ancestors', () => {
    const source = fs.readFileSync(sourcePath, 'utf8');

    expect(source).not.toContain('role="button"');
    expect(source).not.toContain('role="gridcell"');
    expect(source).not.toMatch(/<div[\s\S]*?role="button"[\s\S]*?<Desktop(?:Event|Task)Pill/);
    expect(source).not.toMatch(/<div[\s\S]*?tabIndex=\{0\}[\s\S]*?<Desktop(?:Event|Task)Pill/);
  });

  it('provides a dedicated day selection button in each date header', () => {
    const source = fs.readFileSync(sourcePath, 'utf8');

    expect(source).toMatch(/<button[\s\S]*?type="button"[\s\S]*?aria-label=\{`\$\{ariaLabelByDateStr\[dateStr\]/);
    expect(source).toContain('aria-pressed={isSelected}');
    expect(source).toContain('onClick={() => onSelectDate(dateStr)}');
    expect(source).toContain('data-day-select');
  });
});
