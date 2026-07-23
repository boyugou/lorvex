import { QueryClient } from '@tanstack/react-query';
import { describe, expect, it } from 'vitest';
import type { Task } from '@/lib/ipc/tasks/models';

import {
  applyOptimisticTaskPatch,
  rollbackOptimisticTaskPatch,
} from './optimisticEntity';
import { QK } from './queryKeyHeads';

/**
 * Minimal `Task` factory — fills only the fields the helper inspects
 * (`id`, `status`, `list_id`) plus the ones the tests assert against.
 * Cast at the boundary so the rest of the `Task` schema (HLC version,
 * timestamps, tags, etc.) does not have to be respelled per-test.
 */
function makeTask(overrides: Partial<Task> & { id: string }): Task {
  const base = {
    title: `task-${overrides.id}`,
    body: null,
    raw_input: null,
    ai_notes: null,
    status: 'open',
    list_id: 'list-1',
    tags: null,
    checklist_items: null,
    priority: null,
    due_date: null,
    due_time: null,
    estimated_minutes: null,
    recurrence: null,
    recurrence_exceptions: null,
    depends_on: null,
    spawned_from: null,
    recurrence_group_id: null,
    canonical_occurrence_date: null,
    recurrence_instance_key: null,
    version: '0',
    created_at: '2025-01-01T00:00:00Z',
    updated_at: '2025-01-01T00:00:00Z',
    completed_at: null,
    last_deferred_at: null,
    last_defer_reason: null,
    planned_date: null,
    defer_count: 0,
  };
  return { ...base, ...overrides } as Task;
}

const LIST_KEY = [QK.todayPoolTasks, '2025-01-01'] as const;

function setList(qc: QueryClient, key: readonly unknown[], tasks: Task[]) {
  qc.setQueryData([...key], tasks);
}
function getList(qc: QueryClient, key: readonly unknown[]): Task[] | undefined {
  return qc.getQueryData<Task[]>([...key]);
}

describe('optimisticEntityPatch', () => {
  it('applies the patch to every task-bearing list query containing the id', async () => {
    const qc = new QueryClient();
    const a = makeTask({ id: 'a', priority: 3 });
    const b = makeTask({ id: 'b', priority: 2 });
    setList(qc, LIST_KEY, [a, b]);
    setList(qc, [QK.upcomingTasks, '2025-01-01', 14], [a]);

    await applyOptimisticTaskPatch(qc, 'a', { priority: 1 });

    expect(getList(qc, LIST_KEY)?.find((t) => t.id === 'a')?.priority).toBe(1);
    expect(getList(qc, LIST_KEY)?.find((t) => t.id === 'b')?.priority).toBe(2);
    expect(getList(qc, [QK.upcomingTasks, '2025-01-01', 14])?.[0]?.priority).toBe(1);
  });

  it('rolls back only the patched fields on the source task', async () => {
    const qc = new QueryClient();
    const a = makeTask({ id: 'a', priority: 3, due_date: '2025-01-02' });
    const b = makeTask({ id: 'b', priority: 2 });
    setList(qc, LIST_KEY, [a, b]);

    const snap = await applyOptimisticTaskPatch(qc, 'a', { priority: 1 });
    expect(getList(qc, LIST_KEY)?.find((t) => t.id === 'a')?.priority).toBe(1);

    rollbackOptimisticTaskPatch(qc, snap);
    const restored = getList(qc, LIST_KEY)?.find((t) => t.id === 'a');
    expect(restored?.priority).toBe(3);
    expect(restored?.due_date).toBe('2025-01-02');
    // Sibling task is untouched.
    expect(getList(qc, LIST_KEY)?.find((t) => t.id === 'b')?.priority).toBe(2);
  });

  it('concurrent patches on different fields of the same task compose under failure', async () => {
    // Drag A flips status (eventually fails); drag B flips priority (succeeds).
    // Rolling back A must not revert B.
    const qc = new QueryClient();
    const t = makeTask({ id: 'a', status: 'open', priority: 3 });
    setList(qc, LIST_KEY, [t]);

    const snapA = await applyOptimisticTaskPatch(qc, 'a', { status: 'completed' });
    const snapB = await applyOptimisticTaskPatch(qc, 'a', { priority: 1 });

    // Both patches visible.
    let cur = getList(qc, LIST_KEY)?.[0];
    expect(cur?.status).toBe('completed');
    expect(cur?.priority).toBe(1);

    // A fails, rolls back.
    rollbackOptimisticTaskPatch(qc, snapA);
    cur = getList(qc, LIST_KEY)?.[0];
    expect(cur?.status).toBe('open');
    // B's optimistic priority survives.
    expect(cur?.priority).toBe(1);

    // Later B succeeds (no rollback needed) — verify rollback of B alone
    // also restores only its own field.
    rollbackOptimisticTaskPatch(qc, snapB);
    cur = getList(qc, LIST_KEY)?.[0];
    expect(cur?.priority).toBe(3);
    expect(cur?.status).toBe('open');
  });

  it('concurrent patches on different tasks do not clobber each other on rollback', async () => {
    const qc = new QueryClient();
    const a = makeTask({ id: 'a', priority: 3 });
    const b = makeTask({ id: 'b', priority: 2 });
    setList(qc, LIST_KEY, [a, b]);

    const snapA = await applyOptimisticTaskPatch(qc, 'a', { priority: 1 });
    await applyOptimisticTaskPatch(qc, 'b', { priority: 3 });

    // A fails — only A's priority should revert; B's optimistic value stays.
    rollbackOptimisticTaskPatch(qc, snapA);
    expect(getList(qc, LIST_KEY)?.find((t) => t.id === 'a')?.priority).toBe(3);
    expect(getList(qc, LIST_KEY)?.find((t) => t.id === 'b')?.priority).toBe(3);
  });

  it('is a no-op when the task is missing from every cache entry', async () => {
    const qc = new QueryClient();
    const b = makeTask({ id: 'b', priority: 2 });
    setList(qc, LIST_KEY, [b]);

    const snap = await applyOptimisticTaskPatch(qc, 'missing', { priority: 1 });
    expect(snap.entries).toHaveLength(0);
    expect(getList(qc, LIST_KEY)?.[0]?.priority).toBe(2);

    // Rollback is also a no-op.
    rollbackOptimisticTaskPatch(qc, snap);
    expect(getList(qc, LIST_KEY)?.[0]?.priority).toBe(2);
  });

  it('removes the task from list entries when removeFromCacheIf returns true', async () => {
    // #3670 — patch moves task out of the cached window.
    const qc = new QueryClient();
    const a = makeTask({ id: 'a', due_date: '2025-01-02' });
    const b = makeTask({ id: 'b', due_date: '2025-01-03' });
    setList(qc, LIST_KEY, [a, b]);

    const snap = await applyOptimisticTaskPatch(
      qc,
      'a',
      { due_date: '2025-02-15' },
      { removeFromCacheIf: (task) => (task.due_date ?? '') > '2025-01-31' },
    );

    const list = getList(qc, LIST_KEY);
    expect(list).toHaveLength(1);
    expect(list?.[0]?.id).toBe('b');
    expect(snap.entries[0]?.removed?.index).toBe(0);

    // Rollback re-inserts at original index with original fields.
    rollbackOptimisticTaskPatch(qc, snap);
    const restored = getList(qc, LIST_KEY);
    expect(restored).toHaveLength(2);
    expect(restored?.[0]?.id).toBe('a');
    expect(restored?.[0]?.due_date).toBe('2025-01-02');
    expect(restored?.[1]?.id).toBe('b');
  });

  it('removeFromCacheIf does not remove the single-task `[task, id]` cache', async () => {
    const qc = new QueryClient();
    const t = makeTask({ id: 'a', due_date: '2025-01-02' });
    qc.setQueryData([QK.task, 'a'], t);

    await applyOptimisticTaskPatch(
      qc,
      'a',
      { due_date: '2025-02-15' },
      { removeFromCacheIf: () => true },
    );
    // Single-task detail cache keeps the patched value (correct for
    // the canonical detail view).
    expect(qc.getQueryData<Task>([QK.task, 'a'])?.due_date).toBe('2025-02-15');
  });

  it('removeFromCacheIf rollback no-ops when refetch already re-inserted the task', async () => {
    const qc = new QueryClient();
    const a = makeTask({ id: 'a', due_date: '2025-01-02' });
    setList(qc, LIST_KEY, [a]);

    const snap = await applyOptimisticTaskPatch(
      qc,
      'a',
      { due_date: '2025-02-15' },
      { removeFromCacheIf: () => true },
    );
    expect(getList(qc, LIST_KEY)).toHaveLength(0);

    // Simulate a refetch that re-inserts the task with the new date.
    setList(qc, LIST_KEY, [makeTask({ id: 'a', due_date: '2025-02-15' })]);

    rollbackOptimisticTaskPatch(qc, snap);
    const list = getList(qc, LIST_KEY);
    // No double-insert — exactly one entry, with the prior fields
    // re-applied to the existing task.
    expect(list).toHaveLength(1);
    expect(list?.[0]?.due_date).toBe('2025-01-02');
  });

  it('patches the single-task query shape `[task, id]`', async () => {
    const qc = new QueryClient();
    const t = makeTask({ id: 'a', priority: 3 });
    qc.setQueryData([QK.task, 'a'], t);

    const snap = await applyOptimisticTaskPatch(qc, 'a', { priority: 1 });
    expect(qc.getQueryData<Task>([QK.task, 'a'])?.priority).toBe(1);

    rollbackOptimisticTaskPatch(qc, snap);
    expect(qc.getQueryData<Task>([QK.task, 'a'])?.priority).toBe(3);
  });

  it('captureFields skips keys absent from the source entity (#3682)', async () => {
    // If a patch references a field the source entity does not own,
    // captureFields must skip it — recording `undefined` would cause
    // rollback to write `field: undefined` which silently erases a
    // value a concurrent patch had set.
    const qc = new QueryClient();
    // Build a task that has `priority: 3` but does NOT carry `body`
    // (body absent — `null` is still a real own-property; we want
    // a true "key not present" case). Cast through to omit body.
    const taskWithoutBody = (() => {
      const base = makeTask({ id: 'a', priority: 3 });
      const { body: _omit, ...rest } = base as unknown as Record<string, unknown> & { body: unknown };
      return rest as unknown as Task;
    })();
    setList(qc, LIST_KEY, [taskWithoutBody]);

    const snap = await applyOptimisticTaskPatch(qc, 'a', {
      priority: 1,
      // body is not present on the source — captureFields should skip it.
      body: 'patched-body',
    });

    // The previous-fields snapshot contains `priority` only; `body`
    // is omitted because it wasn't an own-property of the source.
    expect(Object.keys(snap.entries[0]!.previousFields)).toEqual(['priority']);
    expect('body' in snap.entries[0]!.previousFields).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Habit-domain rollback (#3678)
// ---------------------------------------------------------------------------
//
// The generic helper is supposed to work for any identifiable entity.
// Wire up a minimal habit-shaped config and exercise the same
// concurrent-patch invariants we assert for tasks.

import {
  applyOptimisticEntityPatch,
  rollbackOptimisticEntityPatch,
  type OptimisticEntityConfig,
} from './optimisticEntity';

interface FakeHabit {
  id: string;
  completions_today: number;
  target_count: number;
  current_streak: number;
}

const HABIT_HEAD = QK.todaysHabits;

const FAKE_HABIT_CONFIG: OptimisticEntityConfig<FakeHabit> = {
  queryHeads: new Set<string>([HABIT_HEAD]),
  looksLikeEntity: (value: unknown): value is FakeHabit =>
    !!value &&
    typeof value === 'object' &&
    'id' in (value as Record<string, unknown>) &&
    'completions_today' in (value as Record<string, unknown>) &&
    'target_count' in (value as Record<string, unknown>),
};

function makeHabit(id: string, completionsToday = 0): FakeHabit {
  return { id, completions_today: completionsToday, target_count: 1, current_streak: 0 };
}

describe('optimisticEntityPatch — habit domain (#3678)', () => {
  const HABIT_LIST_KEY = [HABIT_HEAD, '2025-01-01'] as const;

  it('per-field rollback restores only the patched field on the source habit', async () => {
    const qc = new QueryClient();
    const a = makeHabit('a', 0);
    const b = makeHabit('b', 0);
    qc.setQueryData([...HABIT_LIST_KEY], [a, b]);

    const snap = await applyOptimisticEntityPatch(qc, FAKE_HABIT_CONFIG, 'a', {
      completions_today: 1,
    });
    expect(qc.getQueryData<FakeHabit[]>([...HABIT_LIST_KEY])?.[0]?.completions_today).toBe(1);

    rollbackOptimisticEntityPatch(qc, FAKE_HABIT_CONFIG, snap);
    const restored = qc.getQueryData<FakeHabit[]>([...HABIT_LIST_KEY]);
    expect(restored?.[0]?.completions_today).toBe(0);
    expect(restored?.[1]?.completions_today).toBe(0);
  });

  it('rollback of habit A does not clobber a concurrent optimistic patch on habit B', async () => {
    // The bug fixed by #3678: full-array snapshot rollback would
    // restore the pre-A array, erasing B's optimistic patch.
    const qc = new QueryClient();
    const a = makeHabit('a', 0);
    const b = makeHabit('b', 0);
    qc.setQueryData([...HABIT_LIST_KEY], [a, b]);

    const snapA = await applyOptimisticEntityPatch(qc, FAKE_HABIT_CONFIG, 'a', {
      completions_today: 1,
    });
    await applyOptimisticEntityPatch(qc, FAKE_HABIT_CONFIG, 'b', {
      completions_today: 1,
    });

    // A fails — its rollback must preserve B's optimistic patch.
    rollbackOptimisticEntityPatch(qc, FAKE_HABIT_CONFIG, snapA);
    const list = qc.getQueryData<FakeHabit[]>([...HABIT_LIST_KEY]);
    expect(list?.find((h) => h.id === 'a')?.completions_today).toBe(0);
    expect(list?.find((h) => h.id === 'b')?.completions_today).toBe(1);
  });

  it('singleEntityCacheRemoval=true removes the single-entity cache when predicate matches (#3686)', async () => {
    const REMOVABLE_CONFIG: OptimisticEntityConfig<FakeHabit> = {
      ...FAKE_HABIT_CONFIG,
      singleEntityCacheRemoval: true,
    };
    const qc = new QueryClient();
    const a = makeHabit('a', 0);
    qc.setQueryData([HABIT_HEAD, 'a'], a);

    const snap = await applyOptimisticEntityPatch(
      qc,
      REMOVABLE_CONFIG,
      'a',
      { completions_today: 1 },
      { removeFromCacheIf: () => true },
    );
    // Single-entity cache was cleared.
    expect(qc.getQueryData<FakeHabit>([HABIT_HEAD, 'a'])).toBeUndefined();

    // Rollback restores the prior entity.
    rollbackOptimisticEntityPatch(qc, REMOVABLE_CONFIG, snap);
    expect(qc.getQueryData<FakeHabit>([HABIT_HEAD, 'a'])?.completions_today).toBe(0);
  });

  it('singleEntityCacheRemoval defaults to false — single-entity cache keeps the patched value (#3686)', async () => {
    const qc = new QueryClient();
    const a = makeHabit('a', 0);
    qc.setQueryData([HABIT_HEAD, 'a'], a);

    await applyOptimisticEntityPatch(
      qc,
      FAKE_HABIT_CONFIG,
      'a',
      { completions_today: 1 },
      { removeFromCacheIf: () => true },
    );
    // Default behavior: single-entity cache keeps the patched value.
    expect(qc.getQueryData<FakeHabit>([HABIT_HEAD, 'a'])?.completions_today).toBe(1);
  });

  // -------------------------------------------------------------------
  // #3695 — additional habit-completion scenarios
  // -------------------------------------------------------------------
  //
  // The hook (`useHabitCompletionActions`) is the consumer of these
  // primitives; the four scenarios below exercise the behaviors the
  // hook depends on (rapid double-tap rollback safety, sequential
  // patch composition, server-patch re-apply, and the
  // refetch-already-ran no-op) at the entity-helper layer where they
  // can be verified without spinning up React.

  it('same-habit rapid double-tap: rolling back the second snapshot leaves the first patch in place', async () => {
    // Tap 1 patches completions_today 0 → 1, tap 2 patches 1 → 2.
    // If tap 2 errors, rolling back its snapshot should restore the
    // post-tap-1 value (1), not the pre-tap-1 value (0). The hook
    // gates same-habit double-taps via pendingHabitsRef, but if the
    // gate ever lets two through (e.g. completion arrives between
    // them), the per-field snapshot must compose cleanly.
    const qc = new QueryClient();
    const a = makeHabit('a', 0);
    qc.setQueryData([...HABIT_LIST_KEY], [a]);

    const snap1 = await applyOptimisticEntityPatch(qc, FAKE_HABIT_CONFIG, 'a', {
      completions_today: 1,
    });
    const snap2 = await applyOptimisticEntityPatch(qc, FAKE_HABIT_CONFIG, 'a', {
      completions_today: 2,
    });
    expect(qc.getQueryData<FakeHabit[]>([...HABIT_LIST_KEY])?.[0]?.completions_today).toBe(2);

    // Tap 2 fails — restores to the post-tap-1 state, not the original.
    rollbackOptimisticEntityPatch(qc, FAKE_HABIT_CONFIG, snap2);
    expect(qc.getQueryData<FakeHabit[]>([...HABIT_LIST_KEY])?.[0]?.completions_today).toBe(1);

    // Tap 1 also rolls back cleanly back to 0.
    rollbackOptimisticEntityPatch(qc, FAKE_HABIT_CONFIG, snap1);
    expect(qc.getQueryData<FakeHabit[]>([...HABIT_LIST_KEY])?.[0]?.completions_today).toBe(0);
  });

  it('rapid-tap gating sketch: a same-habit second snapshot with no intervening apply re-snapshots the optimistic value', async () => {
    // The hook drops a same-habit second tap entirely (pendingHabitsRef
    // hits before mutation runs). At the helper layer this is observed
    // as: if the hook DID let it through, the second snapshot's
    // previousFields would capture the *optimistic* value — meaning
    // rolling back the second snapshot would not return us to the
    // pristine pre-tap state. This test pins that contract so the
    // hook-level gate's importance stays visible.
    const qc = new QueryClient();
    const a = makeHabit('a', 0);
    qc.setQueryData([...HABIT_LIST_KEY], [a]);

    await applyOptimisticEntityPatch(qc, FAKE_HABIT_CONFIG, 'a', { completions_today: 1 });
    const snap2 = await applyOptimisticEntityPatch(qc, FAKE_HABIT_CONFIG, 'a', {
      completions_today: 2,
    });

    // The second snapshot captured `completions_today: 1` (the
    // optimistic value), not `0`. Rolling back snap2 alone returns us
    // to the optimistic-mid state — which is why the hook gate must
    // refuse the second tap on the same habit.
    expect(snap2.entries[0]?.previousFields.completions_today).toBe(1);
  });

  it('onSuccess serverPatch re-apply: applying server fields on top of the optimistic state succeeds without a second snapshot', async () => {
    // After the IPC succeeds, the hook applies `serverPatch(habit,
    // server)` as a fresh `applyOptimisticEntityPatch`. This must
    // overwrite optimistic-only-derived fields (current_streak) with
    // the authoritative server values without disturbing the prior
    // snapshot's previousFields contract.
    const qc = new QueryClient();
    const a = makeHabit('a', 0);
    qc.setQueryData([...HABIT_LIST_KEY], [a]);

    await applyOptimisticEntityPatch(qc, FAKE_HABIT_CONFIG, 'a', {
      completions_today: 1,
    });
    // Server response carries the authoritative streak.
    await applyOptimisticEntityPatch(qc, FAKE_HABIT_CONFIG, 'a', {
      completions_today: 1,
      current_streak: 5,
    });
    const after = qc.getQueryData<FakeHabit[]>([...HABIT_LIST_KEY])?.[0];
    expect(after?.completions_today).toBe(1);
    expect(after?.current_streak).toBe(5);
  });

  it('refetch-already-ran no-op: a snapshot rollback after a refetch wrote new data does not double-revert', async () => {
    // The hook clears pendingHabits on success/error AND lets the
    // post-success invalidate trigger a refetch. If the refetch lands
    // before the rollback (race), the snapshot's stored previousFields
    // are written on top of the freshly-refetched server data — but
    // only on the same id. This test pins that the rollback writes the
    // captured prior fields and nothing else (it does not, e.g., undo
    // the refetch's update of a sibling field).
    const qc = new QueryClient();
    const a = makeHabit('a', 0);
    qc.setQueryData([...HABIT_LIST_KEY], [a]);

    const snap = await applyOptimisticEntityPatch(qc, FAKE_HABIT_CONFIG, 'a', {
      completions_today: 1,
    });
    // Simulate a refetch that landed: streak now reflects server.
    qc.setQueryData([...HABIT_LIST_KEY], [
      { id: 'a', completions_today: 1, target_count: 1, current_streak: 7 },
    ]);

    rollbackOptimisticEntityPatch(qc, FAKE_HABIT_CONFIG, snap);
    const after = qc.getQueryData<FakeHabit[]>([...HABIT_LIST_KEY])?.[0];
    // Captured prior field is restored.
    expect(after?.completions_today).toBe(0);
    // Refetch's authoritative streak is preserved (snapshot didn't
    // capture it, so rollback doesn't touch it).
    expect(after?.current_streak).toBe(7);
  });
});
