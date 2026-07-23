interface KeyboardShortcutsPanelCloseRuntimeDeps {
  addWindowKeydownListener:
    | ((listener: (event: KeyboardEvent) => void) => () => void)
    | null;
  isEditableTarget: (target: EventTarget | null) => boolean;
  onClose: () => void;
}

export function shouldCloseKeyboardShortcutsPanelFromEvent(
  event: Pick<KeyboardEvent, 'altKey' | 'ctrlKey' | 'key' | 'metaKey' | 'target'>,
  isEditableTarget: (target: EventTarget | null) => boolean,
): boolean {
  if (event.key !== '?') return false;
  if (event.metaKey || event.ctrlKey || event.altKey) return false;
  return !isEditableTarget(event.target);
}

export function installKeyboardShortcutsPanelCloseRuntime(
  deps: KeyboardShortcutsPanelCloseRuntimeDeps,
): () => void {
  if (!deps.addWindowKeydownListener) {
    return () => {};
  }

  return deps.addWindowKeydownListener((event) => {
    if (!shouldCloseKeyboardShortcutsPanelFromEvent(event, deps.isEditableTarget)) return;
    event.preventDefault();
    deps.onClose();
  });
}
