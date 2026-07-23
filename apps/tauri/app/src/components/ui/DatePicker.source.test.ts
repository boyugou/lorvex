import { describe, expect, it } from 'vitest';

type FsModule = { readFileSync: (path: string, encoding: string) => string };
type ProcessLike = { cwd: () => string };
type ModuleNS = { createRequire: (url: string) => (mod: string) => unknown };

const proc = (globalThis as unknown as { process: ProcessLike }).process;
const moduleNs = (await import(/* @vite-ignore */ 'node:module' as string)) as unknown as ModuleNS;
const req = moduleNs.createRequire(import.meta.url);
const fs = req('fs') as FsModule;
function readSource(fileName = 'DatePicker.tsx'): string {
  return fs.readFileSync(`${proc.cwd()}/src/components/ui/${fileName}`, 'utf8');
}

function extractConstInitializer(source: string, name: string): string {
  const match = source.match(new RegExp(`const ${name} = ([\\s\\S]*?);\\n`));
  return match?.[1] ?? '';
}

describe('DatePicker desktop dialog accessibility', () => {
  it('does not place the desktop dialog inside an aria-hidden backdrop ancestor', () => {
    const source = readSource('DatePickerDesktopPopover.tsx');

    expect(source).not.toMatch(/aria-hidden="true"[\s\S]*role="dialog"/);
  });

  it('does not claim modal semantics for the desktop anchored popover', () => {
    const source = readSource('DatePickerDesktopPopover.tsx');
    const controllerSource = readSource('DatePicker.controller.ts');

    expect(source).not.toContain('aria-modal="true"');
    expect(controllerSource).toContain('getPopoverLayerClasses');
  });

  it('lets desktop Tab leave the non-modal popover instead of trapping focus', () => {
    const source = readSource('DatePicker.controller.ts');

    expect(source).not.toContain('trapTabFocusWithin');
    expect(source).toContain('skipFocusRestoreRef');
    expect(source).toContain('useFocusRestore({ shouldRestore: () => !skipFocusRestoreRef.current })');
    expect(source).toContain('document.addEventListener(\'focusin\', handleDesktopFocusIn)');
    expect(source).toContain('anchorRef?.current?.contains(target)');
  });

  it('formats day aria labels from calendar-date strings instead of UTC Date objects', () => {
    const source = readSource('DatePickerGrid.tsx');

    expect(source).toContain('formatDatePickerDayAriaLabel');
    expect(source).not.toContain('Date.UTC');
  });

  it('initializes keyboard focus from an enabled day when no value is selected', () => {
    const source = readSource('DatePicker.controller.ts');

    expect(source).toContain('resolveDatePickerInitialFocusYmd');
    expect(source).toContain('resolveDatePickerMonthFocusYmd');
    expect(source).not.toContain('useState<string | null>(value)');
  });

  it('reflects keyboard-focused days through roving DOM focus and visible active-day styling', () => {
    const source = `${readSource('DatePicker.controller.ts')}\n${readSource('DatePickerGrid.tsx')}`;

    expect(source).toContain('dayButtonRefs');
    expect(source).toContain('dayButtonRefs.current.get(focusedDay)?.focus()');
    expect(source).toContain('tabIndex={isFocused ? 0 : -1}');
    expect(source).toContain('data-focused={isFocused ?');
    expect(source).toContain('ring-accent/70');
  });

  it('exposes selected semantics only for the committed selected date', () => {
    const source = readSource('DatePickerGrid.tsx');

    expect(source).toContain('const isSelected = cell.ymd === value;');
    expect(source).toContain('aria-selected={isSelected}');
    expect(source).toContain('aria-pressed={isSelected}');
    expect(source).not.toContain('aria-selected={isFocused}');
  });

  it('applies canonical focus rings to navigation, today, clear, and close controls', () => {
    const source = readSource('DatePickerContent.tsx');

    expect(extractConstInitializer(source, 'navBtnClass')).toContain('focus-ring-soft');
    expect(extractConstInitializer(source, 'navBtnClassSmall')).toContain('focus-ring-soft');
    expect(extractConstInitializer(source, 'clearBtnClass')).toContain('focus-ring-soft');
    expect(extractConstInitializer(source, 'closeBtnClass')).toContain('focus-ring-soft');
    expect(source).toMatch(/className=\{`\$\{isMobile \? 'min-h-11 text-base' : 'text-sm'\}[\s\S]*focus-ring-soft/);
  });
});
