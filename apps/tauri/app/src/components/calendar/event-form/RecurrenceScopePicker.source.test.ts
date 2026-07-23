import { describe, expect, it } from 'vitest';

type FsModule = { readFileSync: (path: string, encoding: string) => string };
type ProcessLike = { cwd: () => string };
type ModuleNS = { createRequire: (url: string) => (mod: string) => unknown };

const proc = (globalThis as unknown as { process: ProcessLike }).process;
const moduleNs = (await import(/* @vite-ignore */ 'node:module' as string)) as unknown as ModuleNS;
const req = moduleNs.createRequire(import.meta.url);
const fs = req('fs') as FsModule;

describe('RecurrenceScopePicker radio keyboard contract', () => {
  it('wires custom radio buttons to roving keyboard behavior', () => {
    const source = fs.readFileSync(`${proc.cwd()}/src/components/calendar/event-form/RecurrenceScopePicker.tsx`, 'utf8');

    expect(source).toContain('onKeyDown={handleRadioGroupKeyDown}');
    expect(source).toContain('handleRecurrenceScopeKeyboardNavigation({');
    expect(source).toContain('key: event.key');
    expect(source).toContain('preventDefault: () => event.preventDefault()');
    expect(source).toContain('selectScope');
    expect(source).toContain('tabIndex={selected ? 0 : -1}');
    expect(source).toContain('buttonRef={(element) => { scopeButtonRefs.current[scope] = element; }}');
    expect(source).toMatch(/if \(event\.key === ' '\) \{\s*event\.preventDefault\(\);\s*onSelect\(\);/);
  });
});
