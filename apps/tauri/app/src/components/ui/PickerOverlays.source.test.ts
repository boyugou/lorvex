import { describe, expect, it } from 'vitest';

type FsModule = { readFileSync: (path: string, encoding: string) => string };
type ProcessLike = { cwd: () => string };
type ModuleNS = { createRequire: (url: string) => (mod: string) => unknown };

const proc = (globalThis as unknown as { process: ProcessLike }).process;
const moduleNs = (await import(/* @vite-ignore */ 'node:module' as string)) as unknown as ModuleNS;
const req = moduleNs.createRequire(import.meta.url);
const fs = req('fs') as FsModule;

const listboxFocusOverlayFiles = [
  'DueDatePickerOverlay.tsx',
  'DurationPickerOverlay.tsx',
  'RecurrencePickerOverlay.tsx',
] as const;

const missingTaskOverlayFiles = [
  'ListPickerOverlay.tsx',
  ...listboxFocusOverlayFiles,
] as const;

describe('picker overlay listbox focus contract', () => {
  it.each(listboxFocusOverlayFiles)('%s focuses the aria-activedescendant listbox itself', (fileName) => {
    const source = fs.readFileSync(`${proc.cwd()}/src/components/ui/${fileName}`, 'utf8');

    expect(source).toContain('aria-activedescendant');
    expect(source).toContain('const listboxRef = useRef<HTMLDivElement>(null)');
    expect(source).toContain('focusTarget={listboxRef}');
    expect(source).toContain('ref={listboxRef}');
    expect(source).toContain('tabIndex={0}');
  });

  it.each(listboxFocusOverlayFiles)('%s handles Enter and Space on the focused listbox container', (fileName) => {
    const source = fs.readFileSync(`${proc.cwd()}/src/components/ui/${fileName}`, 'utf8');

    expect(source).toContain("import { isTaskPickerActivationKey } from './taskPickerKeyboard';");
    expect(source).toMatch(
      /const handlePanelKeyDown = useCallback\([\s\S]*else if \(isTaskPickerActivationKey\(e\.key\)\)/,
    );
  });

  it.each(listboxFocusOverlayFiles)('%s initializes roving focus from the current option', (fileName) => {
    const source = fs.readFileSync(`${proc.cwd()}/src/components/ui/${fileName}`, 'utf8');

    expect(source).not.toContain('const [focusIdx, setFocusIdx] = useState(0);');
    expect(source).toContain("import { useCurrentPickerFocusIndex } from './useCurrentPickerFocusIndex';");
    expect(source).toMatch(
      /const \[focusIdx, setFocusIdx\] = useCurrentPickerFocusIndex\(\{\s*currentKey,/,
    );
  });

  it.each(missingTaskOverlayFiles)('%s closes missing-task overlays from an effect, not render', (fileName) => {
    const source = fs.readFileSync(`${proc.cwd()}/src/components/ui/${fileName}`, 'utf8');

    expect(source).not.toMatch(/if \(!task\) \{\s*onClose\(\);\s*return null;\s*\}/);
    expect(source).toMatch(/useEffect\(\(\) => \{\s*if \(!task\) \{\s*onClose\(\);\s*\}\s*\}, \[task, onClose\]\);/);
    expect(source).toMatch(/if \(!task\) \{\s*return null;\s*\}/);
  });
});
