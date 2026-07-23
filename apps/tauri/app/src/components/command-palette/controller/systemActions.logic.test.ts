/**
 * descriptor-level tests for the command-palette
 * system-action registry. The vitest harness is configured for a
 * Node environment with no DOM (see `app/vitest.config.ts`), so
 * these tests verify the *pure* descriptor list emitted by
 * `systemActions.logic.ts`: id presence, shortcut bindings,
 * confirm-flow gating, and that each descriptor's `run` handler
 * dispatches to the right injected dep.
 *
 * Coverage goals (per #2150 acceptance):
 * 1. EVERY enumerated entry from the issue exists in the registry.
 * 2. Each entry's `run` handler invokes the correct injected dep.
 * 3. Each `confirm`-kind entry carries title + message + label keys.
 * 4. The "Permanent delete task" entry only surfaces when a task is
 *    selected — the destructive surface must not be reachable from
 *    the empty palette by accident.
 * 5. Filter-by-query is substring-only and respects label + desc keys.
 */

import { describe, expect, it, vi } from 'vitest';

import enLocale from '@/locales/en.json';
import type { TranslationKey } from '@/locales/types.generated';
import {
  buildSystemActionDescriptors,
  collectSystemActionTranslationKeys,
  filterSystemActionDescriptors,
  type SelectedTaskContext,
  type SystemActionDeps,
  type SystemActionDescriptor,
  type SystemActionId,
} from './systemActions.logic';

function makeDeps(overrides: Partial<SystemActionDeps> = {}): SystemActionDeps {
  // Every dep is a `vi.fn()` by default so any fired handler can be
  // asserted on individually. Tests pass overrides to inject custom
  // behavior (e.g. throwing a deliberate error to verify error paths).
  return {
    exportData: vi.fn(),
    importData: vi.fn(),
    syncNow: vi.fn(),
    resetSyncRetries: vi.fn(),
    permanentDeleteTask: vi.fn(),
    openShortcuts: vi.fn(),
    toggleLanguage: vi.fn(),
    cycleTheme: vi.fn(),
    openCreateHabit: vi.fn(),
    openCompleteHabit: vi.fn(),
    showMoveTaskHint: vi.fn(),
    purgeCancelled: vi.fn(),
    openDeleteAllData: vi.fn(),
    selectedTask: null,
    ...overrides,
  };
}

function expectDescriptor(
  list: SystemActionDescriptor[],
  id: SystemActionId,
): SystemActionDescriptor {
  const found = list.find((descriptor) => descriptor.id === id);
  expect(found, `expected descriptor ${id} to be present`).toBeDefined();
  // Cast is safe because the assertion above throws on undefined.
  return found as SystemActionDescriptor;
}

describe('buildSystemActionDescriptors — registry coverage', () => {
  it('emits every required #2150 entry when no task is selected', () => {
    const list = buildSystemActionDescriptors(makeDeps());
    const ids = list.map((descriptor) => descriptor.id);

    // Order matters in the palette (sync first, delete-all last) —
    // assert the full ordered set so an accidental reorder fails the
    // test rather than silently changing UX.
    expect(ids).toEqual([
      'system.syncNow',
      'system.exportData',
      'system.importData',
      'system.openDailyReview',
      'system.createHabit',
      'system.completeHabit',
      'system.moveTaskHint',
      'system.toggleLanguage',
      'system.cycleTheme',
      'system.openShortcuts',
      'system.purgeCancelled',
      'system.resetSyncRetries',
      'system.deleteAllData',
    ]);
  });

  it('exposes the permanent-delete entry only when a task is selected', () => {
    const without = buildSystemActionDescriptors(makeDeps());
    expect(without.find((d) => d.id === 'system.permanentDeleteTask')).toBeUndefined();

    const task: SelectedTaskContext = { id: 't-123', title: 'Ship release notes' };
    const withTask = buildSystemActionDescriptors(makeDeps({ selectedTask: task }));
    const entry = expectDescriptor(withTask, 'system.permanentDeleteTask');
    expect(entry.kind).toBe('confirm');
    expect(entry.confirm?.variant).toBe('danger');
  });
});

describe('buildSystemActionDescriptors — handler dispatch', () => {
  it('export entry calls the injected exportData dep on run', async () => {
    const exportData = vi.fn();
    const list = buildSystemActionDescriptors(makeDeps({ exportData }));
    const entry = expectDescriptor(list, 'system.exportData');
    expect(entry.kind).toBe('run');
    await entry.run?.();
    expect(exportData).toHaveBeenCalledTimes(1);
  });

  it('import entry is gated by confirm and routes to importData on run', async () => {
    const importData = vi.fn();
    const list = buildSystemActionDescriptors(makeDeps({ importData }));
    const entry = expectDescriptor(list, 'system.importData');
    expect(entry.kind).toBe('confirm');
    expect(entry.confirm?.titleKey).toBe('palette.importData');
    expect(entry.confirm?.messageKey).toBe('palette.importDataConfirm');
    await entry.run?.();
    expect(importData).toHaveBeenCalledTimes(1);
  });

  it('sync-now entry dispatches to syncNow dep with the bound shortcut hint', async () => {
    const syncNow = vi.fn();
    const list = buildSystemActionDescriptors(makeDeps({ syncNow }));
    const entry = expectDescriptor(list, 'system.syncNow');
    expect(entry.shortcut).toEqual(['Mod', 'Shift', 'S']);
    await entry.run?.();
    expect(syncNow).toHaveBeenCalledTimes(1);
  });

  it('reset-sync-retries entry dispatches to resetSyncRetries on confirm', async () => {
    const resetSyncRetries = vi.fn();
    const list = buildSystemActionDescriptors(makeDeps({ resetSyncRetries }));
    const entry = expectDescriptor(list, 'system.resetSyncRetries');
    expect(entry.kind).toBe('confirm');
    expect(entry.confirm?.variant).toBe('danger');
    await entry.run?.();
    expect(resetSyncRetries).toHaveBeenCalledTimes(1);
  });

  it('permanent-delete entry calls permanentDeleteTask with the selected task', async () => {
    const permanentDeleteTask = vi.fn();
    const task: SelectedTaskContext = { id: 't-7', title: 'Audit failing CI' };
    const list = buildSystemActionDescriptors(
      makeDeps({ permanentDeleteTask, selectedTask: task }),
    );
    const entry = expectDescriptor(list, 'system.permanentDeleteTask');
    await entry.run?.();
    expect(permanentDeleteTask).toHaveBeenCalledTimes(1);
    expect(permanentDeleteTask).toHaveBeenCalledWith(task);
  });

  it('shortcuts entry advertises the `?` accelerator', async () => {
    const openShortcuts = vi.fn();
    const list = buildSystemActionDescriptors(makeDeps({ openShortcuts }));
    const entry = expectDescriptor(list, 'system.openShortcuts');
    expect(entry.shortcut).toEqual(['?']);
    await entry.run?.();
    expect(openShortcuts).toHaveBeenCalledTimes(1);
  });

  it('language toggle and theme cycle route to their deps', async () => {
    const deps = makeDeps();
    const list = buildSystemActionDescriptors(deps);

    await expectDescriptor(list, 'system.toggleLanguage').run?.();
    await expectDescriptor(list, 'system.cycleTheme').run?.();

    expect(deps.toggleLanguage).toHaveBeenCalledTimes(1);
    expect(deps.cycleTheme).toHaveBeenCalledTimes(1);
  });

  it('habit, daily review, move-task hint, and danger zone link route correctly', async () => {
    const deps = makeDeps();
    const list = buildSystemActionDescriptors(deps);

    const dailyReview = expectDescriptor(list, 'system.openDailyReview');
    expect(dailyReview.kind).toBe('nav');
    expect(dailyReview.navTo).toEqual({ type: 'daily_review' });

    await expectDescriptor(list, 'system.createHabit').run?.();
    await expectDescriptor(list, 'system.moveTaskHint').run?.();
    await expectDescriptor(list, 'system.purgeCancelled').run?.();
    await expectDescriptor(list, 'system.deleteAllData').run?.();

    await expectDescriptor(list, 'system.completeHabit').run?.();

    expect(deps.openCreateHabit).toHaveBeenCalledTimes(1);
    expect(deps.openCompleteHabit).toHaveBeenCalledTimes(1);
    expect(deps.showMoveTaskHint).toHaveBeenCalledTimes(1);
    expect(deps.purgeCancelled).toHaveBeenCalledTimes(1);
    expect(deps.openDeleteAllData).toHaveBeenCalledTimes(1);
  });
});

describe('buildSystemActionDescriptors — confirm flow shape', () => {
  it.each([
    ['system.importData', 'default'],
    ['system.permanentDeleteTask', 'danger'],
    ['system.purgeCancelled', 'danger'],
    ['system.resetSyncRetries', 'danger'],
  ] as const)(
    '%s requires a confirm modal with the correct variant (%s)',
    (id, variant) => {
      const task: SelectedTaskContext = { id: 't', title: 'X' };
      const list = buildSystemActionDescriptors(makeDeps({ selectedTask: task }));
      const entry = expectDescriptor(list, id);
      expect(entry.kind).toBe('confirm');
      expect(entry.confirm).toBeDefined();
      expect(entry.confirm?.titleKey).toBeTruthy();
      expect(entry.confirm?.messageKey).toBeTruthy();
      expect(entry.confirm?.variant).toBe(variant);
    },
  );
});

describe('filterSystemActionDescriptors', () => {
  it('returns the full list for an empty query', () => {
    const list = buildSystemActionDescriptors(makeDeps());
    const filtered = filterSystemActionDescriptors(list, '', () => '');
    expect(filtered).toEqual(list);
  });

  it('substring-matches the localized label', () => {
    const list = buildSystemActionDescriptors(makeDeps());
    const filtered = filterSystemActionDescriptors(
      list,
      'export',
      (key) => enLocale[key as keyof typeof enLocale] ?? '',
    );
    const ids = filtered.map((d) => d.id);
    expect(ids).toContain('system.exportData');
    expect(ids).not.toContain('system.syncNow');
  });

  it('falls through to the description when the label does not match', () => {
    const list = buildSystemActionDescriptors(makeDeps());
    const filtered = filterSystemActionDescriptors(
      list,
      'portable snapshot',
      (key) => enLocale[key as keyof typeof enLocale] ?? '',
    );
    expect(filtered.map((d) => d.id)).toEqual(['system.exportData']);
  });

  it('returns an empty list when nothing matches', () => {
    const list = buildSystemActionDescriptors(makeDeps());
    const filtered = filterSystemActionDescriptors(
      list,
      'no-such-action-anywhere',
      (key) => enLocale[key as keyof typeof enLocale] ?? '',
    );
    expect(filtered).toEqual([]);
  });
});

describe('translation key registry', () => {
  it('every descriptor key resolves in en.ts', () => {
    const task: SelectedTaskContext = { id: 't', title: 'Title' };
    const list = buildSystemActionDescriptors(makeDeps({ selectedTask: task }));
    const keys = collectSystemActionTranslationKeys(list);

    // Sanity: at minimum a label, desc, and confirm strings for every
    // entry. The exact length is asserted as a low-water mark so a
    // future addition of new entries doesn't quietly drop tests below
    // the current bar.
    expect(keys.length).toBeGreaterThanOrEqual(20);

    for (const key of keys) {
      const value = (enLocale as Record<TranslationKey, string>)[key];
      expect(value, `expected en.ts to define translation for ${key}`).toBeTruthy();
    }
  });
});
