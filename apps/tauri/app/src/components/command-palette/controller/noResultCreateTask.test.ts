import type { KeyboardEvent as ReactKeyboardEvent } from 'react';
import { describe, expect, it, vi } from 'vitest';

vi.mock('react', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react')>();
  return {
    ...actual,
    useCallback: <T extends (...args: never[]) => unknown>(fn: T) => fn,
  };
});

vi.mock('@/lib/ipc/tasks/mutations/lifecycle', () => ({
  reopenTask: vi.fn(),
}));

import { createNoResultCreateTaskItem } from './results';
import { usePaletteKeyboard } from './keyboard';

type TestKeyboardEvent = ReactKeyboardEvent<HTMLInputElement> & {
  preventDefault: ReturnType<typeof vi.fn>;
  stopPropagation: ReturnType<typeof vi.fn>;
};

function createEnterEvent(): TestKeyboardEvent {
  return {
    altKey: false,
    key: 'Enter',
    metaKey: false,
    nativeEvent: { isComposing: false, key: 'Enter' },
    preventDefault: vi.fn(),
    shiftKey: false,
    stopPropagation: vi.fn(),
  } as unknown as TestKeyboardEvent;
}

describe('command palette no-result create-task keyboard path', () => {
  it('activates the no-result create-task option with Enter', () => {
    const onClose = vi.fn();
    const onQuickCapture = vi.fn();
    const item = createNoResultCreateTaskItem({
      onClose,
      onQuickCapture,
      query: '  Draft launch notes  ',
      t: (key: string) => (key === 'palette.createTask' ? 'Create task' : key),
    });
    const { handleKeyDown } = usePaletteKeyboard({
      shelveListFromPalette: vi.fn(),
      cancelFromPalette: vi.fn(),
      completeFromPalette: vi.fn(),
      deferFromPalette: vi.fn(),
      deleteListFromPalette: vi.fn(),
      isComposing: false,
      keyedResults: [{ key: 'create-task#0', item }],
      lists: [],
      moveTask: null,
      onClose,
      onNavigate: vi.fn(),
      onSelectTask: vi.fn(),
      query: 'Draft launch notes',
      runPaletteMutation: vi.fn(),
      selectedIdx: 0,
      setMoveTask: vi.fn(),
      setQuery: vi.fn(),
      setSelectedIdx: vi.fn(),
    });
    const event = createEnterEvent();

    handleKeyDown(event);

    expect(event.preventDefault).toHaveBeenCalled();
    expect(event.stopPropagation).toHaveBeenCalled();
    expect(onClose).toHaveBeenCalledOnce();
    expect(onQuickCapture).toHaveBeenCalledWith({ title: 'Draft launch notes' });
  });
});
