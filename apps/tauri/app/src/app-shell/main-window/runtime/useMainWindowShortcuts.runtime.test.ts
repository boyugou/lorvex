import { describe, expect, it } from 'vitest';
import { scheduleGlobalModalEscapeClose } from '../../../components/ui/overlay/ModalShell';
import { resolveMainWindowShortcutAction } from './useMainWindowShortcuts.runtime';

const baseEvent = {
  defaultPrevented: false,
  isComposing: false,
  key: 'Escape',
};

const baseState = {
  selectedTaskId: null,
  showCapture: false,
  showPalette: false,
  usesMobileLayout: false,
};

describe('resolveMainWindowShortcutAction', () => {
  it('ignores nested Escape events that have already been consumed', () => {
    expect(
      resolveMainWindowShortcutAction(
        { ...baseEvent, defaultPrevented: true },
        { ...baseState, showCapture: true },
      ),
    ).toBe('none');
  });

  it('does not treat IME composition Escape as a global dismiss', () => {
    expect(
      resolveMainWindowShortcutAction(
        { ...baseEvent, isComposing: true },
        { ...baseState, showCapture: true },
      ),
    ).toBe('none');
  });

  it('ignores Escape events already owned by the modal stack', () => {
    const scheduled: Array<() => void> = [];
    const event = { ...baseEvent };

    scheduleGlobalModalEscapeClose(event, () => {}, (cb) => {
      scheduled.push(cb);
    });

    expect(
      resolveMainWindowShortcutAction(event, {
        ...baseState,
        selectedTaskId: 'task-1',
      }),
    ).toBe('none');
    expect(scheduled).toHaveLength(1);
  });

  it('ignores Escape from editable targets while task detail is open', () => {
    expect(
      resolveMainWindowShortcutAction(
        { ...baseEvent, target: { tagName: 'INPUT' } as unknown as EventTarget },
        {
          ...baseState,
          selectedTaskId: 'task-1',
        },
      ),
    ).toBe('none');
  });

  it('lets modal Escape handling own quick capture while preserving other desktop Escape actions', () => {
    expect(
      resolveMainWindowShortcutAction(baseEvent, {
        ...baseState,
        selectedTaskId: 'task-1',
        showCapture: true,
        showPalette: true,
      }),
    ).toBe('close-command-palette');
    expect(
      resolveMainWindowShortcutAction(baseEvent, {
        ...baseState,
        selectedTaskId: 'task-1',
        showCapture: true,
      }),
    ).toBe('none');
    expect(
      resolveMainWindowShortcutAction(baseEvent, {
        ...baseState,
        selectedTaskId: 'task-1',
      }),
    ).toBe('clear-selected-task');
  });
});
