/**
 * Contract test: every `useMutation` in `app/src` must flow through
 * `defineEntityHooks` or a documented bespoke helper, not a direct
 * `@tanstack/react-query` import in a component / hook module.
 *
 * The factory at `lib/query/defineEntityHooks.ts` and the optimistic
 * sweep at `lib/query/optimisticEntity.ts` are the canonical primitives.
 * `lib/query/usePreference.ts` is the canonical preference-write
 * helper. Files that route a hand-rolled `useMutation` for one of the
 * documented bespoke reasons (multi-IPC fan-out with `Promise.allSettled`,
 * per-entity optimistic sweep with rollback, cache-only side effects)
 * are explicitly allowlisted below.
 *
 * The allowlist is a closing door: every entry must point at a
 * docblock at the top of the file explaining why the bespoke shape
 * is correct.
 */

import { describe, expect, it } from 'vitest';

type FsNS = {
  readFileSync: (path: string, encoding: 'utf8') => string;
  readdirSync: (path: string) => string[];
  statSync: (path: string) => { isDirectory(): boolean; isFile(): boolean };
};
type PathNS = {
  join: (...parts: string[]) => string;
  relative: (from: string, to: string) => string;
  resolve: (...parts: string[]) => string;
};

const fs = (await import(/* @vite-ignore */ 'node:fs' as string)) as unknown as FsNS;
const path = (await import(/* @vite-ignore */ 'node:path' as string)) as unknown as PathNS;

// Tests run with cwd = `app/`, so `src` is the scan root.
const APP_SRC = path.resolve('src');

/**
 * Files allowed to import `useMutation` directly from
 * `@tanstack/react-query`. Paths are relative to `app/src` and use
 * forward slashes. Every entry has a comment explaining the bespoke
 * contract; see also the docblock at the top of each listed file.
 */
const DIRECT_USE_MUTATION_ALLOWLIST: ReadonlySet<string> = new Set([
  // Canonical factory / primitive. Owns `useMutation`.
  'lib/query/defineEntityHooks.ts',
  // Preference cache write contract — bespoke optimistic seed + revert
  // tied to the typed PreferenceKey registry.
  'lib/query/usePreference.ts',
  // Habit completion: per-entity optimistic sweep + rollback via
  // `applyOptimisticEntityPatch`. The factory's single-key invalidate
  // shape can't cover fan-out across todaysHabits + habitsWithStats
  // simultaneously; documented in the file.
  'components/habits/useHabitCompletionActions.ts',
  // Reschedule-overdue batch: Promise.allSettled fan-out producing an
  // AggregateError with a `partial` flag that branches toast lane and
  // invalidation. Factory can't express either branch.
  'components/today-view/sections/useDashboardSectionActions.ts',
  // Saved-query CRUD: keys scoped per view-type, not a single entity
  // head; the helper builds keys imperatively.
  'lib/hooks/useSavedQueries.ts',
  // Kanban column moves: dispatches one of three IPCs based on the
  // target column (complete / reopen / updateTask) plus optimistic
  // local state for the drop indicator.
  'components/kanban/useKanbanColumnActions.ts',
  // Eisenhower quadrant moves: same shape as kanban — IPC choice
  // depends on the target quadrant.
  'components/eisenhower/useEisenhowerPriorityActions.ts',
  // Schedule-timeline ops: batch reorder + per-block complete branch
  // share local timeline state and per-action toasts.
  'components/schedule-timeline/useScheduleTimelineActions.ts',
]);

const SOURCE_EXTENSIONS = new Set(['.ts', '.tsx']);
const SKIP_DIRS = new Set(['node_modules', '__snapshots__']);

function walk(dir: string, acc: string[] = []): string[] {
  for (const entry of fs.readdirSync(dir)) {
    if (SKIP_DIRS.has(entry)) continue;
    const full = path.join(dir, entry);
    const stat = fs.statSync(full);
    if (stat.isDirectory()) {
      walk(full, acc);
    } else if (stat.isFile()) {
      const dot = entry.lastIndexOf('.');
      if (dot === -1) continue;
      const ext = entry.slice(dot);
      if (!SOURCE_EXTENSIONS.has(ext)) continue;
      // Skip test files — direct `useMutation` use inside a test
      // renderer is the point of the test and not subject to the
      // contract.
      if (entry.endsWith('.test.ts') || entry.endsWith('.test.tsx')) continue;
      acc.push(full);
    }
  }
  return acc;
}

// Match `useMutation` listed among the named imports from
// `@tanstack/react-query`. Handles multi-line / type-only imports.
const TANSTACK_IMPORT_RE =
  /import\s+(?:type\s+)?\{([^}]+)\}\s*from\s*['"]@tanstack\/react-query['"]/g;

function fileUsesDirectUseMutation(source: string): boolean {
  TANSTACK_IMPORT_RE.lastIndex = 0;
  let match: RegExpExecArray | null;
  while ((match = TANSTACK_IMPORT_RE.exec(source))) {
    const namedSection = match[1]!;
    const names = namedSection
      .split(',')
      .map((name) => name.trim().replace(/^type\s+/, '').split(/\s+as\s+/)[0]!.trim())
      .filter((name) => name.length > 0);
    if (names.includes('useMutation')) return true;
  }
  return false;
}

describe('useMutation direct-import contract', () => {
  const sourceFiles = walk(APP_SRC).map((abs) => ({
    abs,
    rel: path.relative(APP_SRC, abs).split('\\').join('/'),
  }));

  it('app/src contains source files to scan (sanity check)', () => {
    expect(sourceFiles.length).toBeGreaterThan(0);
  });

  it('every direct `useMutation` import sits in the bespoke allowlist', () => {
    const offenders: string[] = [];
    for (const { abs, rel } of sourceFiles) {
      const source = fs.readFileSync(abs, 'utf8');
      if (!fileUsesDirectUseMutation(source)) continue;
      if (DIRECT_USE_MUTATION_ALLOWLIST.has(rel)) continue;
      offenders.push(rel);
    }
    expect(offenders).toEqual([]);
  });

  it('every allowlist entry still imports `useMutation` (drift guard)', () => {
    const stale: string[] = [];
    for (const rel of DIRECT_USE_MUTATION_ALLOWLIST) {
      const abs = path.join(APP_SRC, rel);
      let source: string;
      try {
        source = fs.readFileSync(abs, 'utf8');
      } catch {
        stale.push(`${rel} (missing)`);
        continue;
      }
      if (!fileUsesDirectUseMutation(source)) {
        stale.push(`${rel} (no longer imports useMutation)`);
      }
    }
    expect(stale).toEqual([]);
  });
});
