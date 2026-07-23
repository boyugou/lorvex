import { isEditableTarget } from '@/lib/editableTarget';
import { isEscapeEventHandled } from '@/lib/focus/escapeKeyOwnership';

export type MainWindowShortcutAction =
  | 'clear-selected-task'
  | 'close-command-palette'
  | 'none';

export interface MainWindowShortcutEvent {
  defaultPrevented: boolean;
  isComposing: boolean;
  key: string;
  target?: EventTarget | null;
}

export interface MainWindowShortcutState {
  selectedTaskId: string | null;
  showCapture: boolean;
  showPalette: boolean;
  usesMobileLayout: boolean;
}

export function resolveMainWindowShortcutAction(
  event: MainWindowShortcutEvent,
  state: MainWindowShortcutState,
): MainWindowShortcutAction {
  if (state.usesMobileLayout || event.defaultPrevented || event.isComposing) {
    return 'none';
  }

  if (event.key !== 'Escape') {
    return 'none';
  }

  if (isEscapeEventHandled(event) || isEditableTarget(event.target ?? null)) {
    return 'none';
  }

  if (state.showPalette) {
    return 'close-command-palette';
  }

  if (state.showCapture) {
    return 'none';
  }

  if (state.selectedTaskId !== null) {
    return 'clear-selected-task';
  }

  return 'none';
}
