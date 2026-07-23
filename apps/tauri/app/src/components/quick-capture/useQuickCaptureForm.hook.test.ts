import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { ListWithCount } from '@/lib/ipc/tasks/models';

type EffectCleanup = void | (() => void);
type EffectSlot = {
  cleanup: EffectCleanup;
  deps: readonly unknown[] | undefined;
  effect: (() => EffectCleanup) | null;
  pending: boolean;
};
type MemoSlot = {
  deps: readonly unknown[] | undefined;
  value: unknown;
};

const hookRuntime = vi.hoisted(() => {
  const stateSlots: unknown[] = [];
  const refSlots: Array<{ current: unknown }> = [];
  const memoSlots: MemoSlot[] = [];
  const effectSlots: EffectSlot[] = [];
  let stateCursor = 0;
  let refCursor = 0;
  let memoCursor = 0;
  let effectCursor = 0;

  function depsChanged(
    previous: readonly unknown[] | undefined,
    next: readonly unknown[] | undefined,
  ): boolean {
    if (!previous || !next || previous.length !== next.length) return true;
    return next.some((value, index) => !Object.is(value, previous[index]));
  }

  return {
    resetAll() {
      stateSlots.length = 0;
      refSlots.length = 0;
      memoSlots.length = 0;
      effectSlots.length = 0;
      stateCursor = 0;
      refCursor = 0;
      memoCursor = 0;
      effectCursor = 0;
    },
    beginRender() {
      stateCursor = 0;
      refCursor = 0;
      memoCursor = 0;
      effectCursor = 0;
    },
    runPendingEffects() {
      for (const slot of effectSlots) {
        if (!slot.pending || !slot.effect) continue;
        if (typeof slot.cleanup === 'function') slot.cleanup();
        slot.cleanup = slot.effect();
        slot.pending = false;
      }
    },
    useEffect(effect: () => EffectCleanup, deps?: readonly unknown[]) {
      const slot = effectSlots[effectCursor++] ?? {
        cleanup: undefined,
        deps: undefined,
        effect: null,
        pending: false,
      };
      if (depsChanged(slot.deps, deps)) {
        slot.deps = deps;
        slot.effect = effect;
        slot.pending = true;
      }
      effectSlots[effectCursor - 1] = slot;
    },
    useMemo<T>(factory: () => T, deps?: readonly unknown[]): T {
      const slot = memoSlots[memoCursor];
      if (!slot || depsChanged(slot.deps, deps)) {
        const value = factory();
        memoSlots[memoCursor++] = { deps, value };
        return value;
      }
      memoCursor += 1;
      return slot.value as T;
    },
    // useCallback shares memo's slot semantics — same dependency check,
    // same per-render identity stability — so it shells out to the same
    // memoSlot machinery. Without this entry, hooks that legitimately
    // need stable callback references (e.g. `requestClose` in
    // useQuickCaptureForm, gated discard-confirm) fail at runtime here
    // with "No 'useCallback' export is defined on the 'react' mock."
    useCallback<T extends (...args: never[]) => unknown>(
      callback: T,
      deps?: readonly unknown[],
    ): T {
      const slot = memoSlots[memoCursor];
      if (!slot || depsChanged(slot.deps, deps)) {
        memoSlots[memoCursor++] = { deps, value: callback };
        return callback;
      }
      memoCursor += 1;
      return slot.value as T;
    },
    useRef<T>(initial: T) {
      if (refCursor >= refSlots.length) {
        refSlots.push({ current: initial });
      }
      return refSlots[refCursor++] as { current: T };
    },
    useState<T>(initial: T | (() => T)) {
      const index = stateCursor++;
      if (index >= stateSlots.length) {
        stateSlots.push(typeof initial === 'function' ? (initial as () => T)() : initial);
      }
      const setState = (next: T | ((current: T) => T)) => {
        const current = stateSlots[index] as T;
        stateSlots[index] = typeof next === 'function'
          ? (next as (current: T) => T)(current)
          : next;
      };
      return [stateSlots[index] as T, setState] as const;
    },
  };
});

const setupStatusMock = vi.hoisted(() => ({
  getSetupStatus: vi.fn(),
}));

const confirmMock = vi.hoisted(() => ({
  confirm: vi.fn(),
}));

vi.mock('react', () => ({
  useCallback: hookRuntime.useCallback,
  useEffect: hookRuntime.useEffect,
  useMemo: hookRuntime.useMemo,
  useRef: hookRuntime.useRef,
  useState: hookRuntime.useState,
}));

vi.mock('@tanstack/react-query', () => ({
  useQueryClient: () => ({}),
}));

vi.mock('../../lib/useMounted', () => ({
  useMounted: () => ({ current: true }),
}));

vi.mock('../../lib/ipc', () => ({
  getDeviceState: vi.fn(),
  quickCapture: vi.fn(),
  setDeviceState: vi.fn(),
}));

vi.mock('../../lib/ipc/settings', () => ({
  getSetupStatus: setupStatusMock.getSetupStatus,
}));

vi.mock('../../lib/dialogs/confirm', () => ({
  confirm: confirmMock.confirm,
}));

vi.mock('../../lib/preferences/keys', () => ({
  DEV_FIRST_TASK_CELEBRATED: 'dev:first-task-celebrated',
}));

vi.mock('../../lib/errors/errorLogging', () => ({
  reportClientError: vi.fn(),
}));

vi.mock('../../lib/query/queryKeys', () => ({
  invalidateListContextTaskWriteQueries: vi.fn(),
}));

vi.mock('../../lib/i18n', () => ({
  useI18n: () => ({
    format: (key: string) => key,
    formatNumber: (value: number) => String(value),
    locale: 'en',
    t: (key: string) => key,
  }),
}));

vi.mock('../../lib/shortcuts', () => ({
  formatShortcut: (keys: string[]) => keys.join('+'),
}));

vi.mock('../../lib/notifications/toast', () => ({
  toast: {
    error: vi.fn(),
    errorWithDetail: vi.fn(),
    info: vi.fn(),
    success: vi.fn(),
  },
}));

vi.mock('../../lib/dayContext', () => ({
  getNextMondayYmd: () => '2026-05-04',
  getNextWeekendYmd: () => '2026-05-02',
  useConfiguredDayContext: () => ({
    timezone: 'America/New_York',
    todayYmd: '2026-05-01',
    tomorrowYmd: '2026-05-02',
  }),
  ymdFromDateParts: () => '2026-05-01',
}));

vi.mock('../../lib/dateParser', () => ({
  parseDateFromText: () => null,
}));

vi.mock('../../lib/storage/uiState', () => ({
  getUIStateString: () => '',
  removeUIState: vi.fn(),
  setUIState: vi.fn(),
}));

import { useQuickCaptureForm } from './useQuickCaptureForm';

function makeList(id: string): ListWithCount {
  return {
    id,
    name: id,
    color: null,
    icon: null,
    description: null,
    ai_notes: null,
    created_at: '2026-01-01T00:00:00Z',
    updated_at: '2026-01-01T00:00:00Z',
    open_count: 0,
  };
}

function renderQuickCaptureForm(
  lists: ListWithCount[],
  options: {
    initialData?: Parameters<typeof useQuickCaptureForm>[0]['initialData'];
    onClose?: () => void;
    sessionId?: number;
  } = {},
) {
  hookRuntime.beginRender();
  // eslint-disable-next-line react-hooks/rules-of-hooks -- test render harness; behaves as a synchronous hook caller for `hookRuntime`.
  const result = useQuickCaptureForm({
    initialData: options.initialData,
    lists,
    onClose: options.onClose ?? vi.fn(),
    sessionId: options.sessionId,
  });
  hookRuntime.runPendingEffects();
  return result;
}

describe('useQuickCaptureForm setup-status reload lifecycle', () => {
  beforeEach(() => {
    hookRuntime.resetAll();
    confirmMock.confirm.mockReset();
    setupStatusMock.getSetupStatus.mockReset();
    setupStatusMock.getSetupStatus.mockResolvedValue({
      default_list_id: null,
      default_list_ready: false,
      normal_task_creation_ready: false,
    });
    vi.stubGlobal('localStorage', {
      getItem: vi.fn(() => null),
      removeItem: vi.fn(),
      setItem: vi.fn(),
    });
  });

  it('reloads setup status exactly once when lists arrive after an empty initial snapshot', () => {
    renderQuickCaptureForm([]);
    expect(setupStatusMock.getSetupStatus).toHaveBeenCalledTimes(1);

    renderQuickCaptureForm([makeList('list-a')]);
    expect(setupStatusMock.getSetupStatus).toHaveBeenCalledTimes(2);

    renderQuickCaptureForm([makeList('list-a')]);
    expect(setupStatusMock.getSetupStatus).toHaveBeenCalledTimes(2);
  });

  it('clears the persisted autosave draft when confirmed discard closes a dirty form', async () => {
    const onClose = vi.fn();
    const removeItem = vi.fn();
    confirmMock.confirm.mockResolvedValue(true);
    vi.stubGlobal('localStorage', {
      getItem: vi.fn(() => null),
      removeItem,
      setItem: vi.fn(),
    });

    let form = renderQuickCaptureForm([makeList('list-a')], { onClose });
    form.setTitle('Discard this draft');
    form = renderQuickCaptureForm([makeList('list-a')], { onClose });

    await form.requestClose();

    expect(confirmMock.confirm).toHaveBeenCalledTimes(1);
    expect(removeItem).toHaveBeenCalledWith('lorvex.quickCapture.draft');
    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('refreshes initial form state when the active quick-capture session changes', () => {
    const lists = [makeList('list-a'), makeList('list-b')];
    const firstSession = {
      title: 'First payload',
      list: 'list-a',
      due: '2026-05-10',
      priority: 1 as const,
    };
    const secondSession = {
      title: 'Second payload',
      list: 'list-b',
      due: '2026-05-11',
      priority: 2 as const,
    };

    let form = renderQuickCaptureForm(lists, {
      initialData: firstSession,
      sessionId: 1,
    });
    expect(form.title).toBe('First payload');
    expect(form.selectedListId).toBe('list-a');
    expect(form.customDate).toBe('2026-05-10');
    expect(form.priority).toBe(1);

    form.setTitle('User typed over the first session');
    form.setTagsInput('stale-tag');
    form = renderQuickCaptureForm(lists, {
      initialData: firstSession,
      sessionId: 1,
    });
    expect(form.title).toBe('User typed over the first session');
    expect(form.tagsInput).toBe('stale-tag');

    renderQuickCaptureForm(lists, {
      initialData: secondSession,
      sessionId: 2,
    });
    form = renderQuickCaptureForm(lists, {
      initialData: secondSession,
      sessionId: 2,
    });

    expect(form.title).toBe('Second payload');
    expect(form.selectedListId).toBe('list-b');
    expect(form.dateOption).toBe('custom');
    expect(form.customDate).toBe('2026-05-11');
    expect(form.priority).toBe(2);
    expect(form.tagsInput).toBe('');
  });
});
