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

describe('task drag keyboard metadata', () => {
  it('applies draggable metadata to the focusable TaskCardContent button', () => {
    const taskCard = source('src/components/task-card/TaskCard.tsx');
    const taskCardContent = source('src/components/task-card/TaskCardContent.tsx');
    const support = source('src/components/task-card/support.ts');

    expect(support).toContain('taskButtonAriaDescription?: string');
    expect(support).toContain('taskButtonAriaRoleDescription?: string');
    expect(support).toContain('taskButtonAriaKeyShortcuts?: string');
    expect(taskCard).toContain('taskButtonAriaDescription={taskButtonAriaDescription}');
    expect(taskCard).toContain('taskButtonAriaRoleDescription={taskButtonAriaRoleDescription}');
    expect(taskCard).toContain('taskButtonAriaKeyShortcuts={taskButtonAriaKeyShortcuts}');
    expect(taskCardContent).toContain('aria-roledescription={taskButtonAriaRoleDescription}');
    expect(taskCardContent).toContain('aria-keyshortcuts={taskButtonAriaKeyShortcuts}');
  });

  it('keeps Eisenhower drag metadata off the non-focusable wrapper', () => {
    // The Eisenhower row component lives next to the view's
    // per-folder split (see `eisenhower/EisenhowerTaskRow.tsx`).
    const sourceText = source('src/components/eisenhower/EisenhowerTaskRow.tsx');

    expect(sourceText).toContain("import { ariaKeyShortcutsForModChord } from '@/lib/shortcuts';");
    expect(sourceText).toContain('taskButtonAriaRoleDescription="draggable"');
    expect(sourceText).toContain("ariaKeyShortcutsForModChord(['Mod', 'ArrowLeft'])");
    expect(sourceText).not.toMatch(/<div[\s\S]{0,240}aria-roledescription="draggable"[\s\S]{0,160}<SwipeableTaskCard/);
    expect(sourceText).not.toMatch(/<div[\s\S]{0,240}aria-keyshortcuts="Control\+ArrowLeft/);
  });

  it('keeps Kanban drag metadata off the non-focusable wrapper', () => {
    // The Kanban row component lives next to the view's
    // per-folder split (see `kanban/Column.tsx`).
    const sourceText = source('src/components/kanban/Column.tsx');

    expect(sourceText).toContain("import { ariaKeyShortcutsForModChord } from '@/lib/shortcuts';");
    expect(sourceText).toContain('taskButtonAriaRoleDescription="draggable"');
    expect(sourceText).toContain("ariaKeyShortcutsForModChord(['Mod', 'ArrowLeft'])");
    expect(sourceText).toContain("ariaKeyShortcutsForModChord(['Mod', 'ArrowRight'])");
    expect(sourceText).not.toMatch(/<div[\s\S]{0,240}aria-roledescription="draggable"[\s\S]{0,160}<SwipeableTaskCard/);
    expect(sourceText).not.toMatch(/<div[\s\S]{0,240}aria-keyshortcuts="Control\+ArrowLeft/);
  });

  it('keeps focus-list reorder metadata off the non-focusable wrapper', () => {
    const sourceText = source('src/components/today-view/FocusSection.tsx');

    expect(sourceText).toContain('taskButtonAriaDescription={t(\'list.reorderHint\')}');
    expect(sourceText).toContain('taskButtonAriaRoleDescription="draggable"');
    expect(sourceText).toContain('taskButtonAriaKeyShortcuts="Alt+ArrowUp Alt+ArrowDown"');
    expect(sourceText).not.toMatch(/<div[\s\S]{0,260}aria-roledescription="draggable"[\s\S]{0,180}<SwipeableTaskCard/);
    expect(sourceText).not.toMatch(/<div[\s\S]{0,260}aria-keyshortcuts="Alt\+ArrowUp Alt\+ArrowDown"/);
  });
});
