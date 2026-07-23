type HabitFormKeydownTarget = Pick<Window, 'addEventListener' | 'removeEventListener'>;

interface HabitFormEscapeRuntimeDeps {
  windowTarget?: HabitFormKeydownTarget | undefined;
  getFormRoot: () => HTMLElement | null;
  requestClose: () => void | Promise<void>;
}

export function shouldRequestHabitFormCloseFromEscape(
  event: Pick<KeyboardEvent, 'defaultPrevented' | 'key' | 'isComposing'> & {
    target?: EventTarget | null;
    formRoot?: Pick<HTMLElement, 'contains'> | null;
  },
): boolean {
  if (event.key !== 'Escape' || event.isComposing || event.defaultPrevented) return false;
  if (event.formRoot) {
    if (!event.target) return false;
    return event.formRoot.contains(event.target as Node);
  }
  return true;
}

export function installHabitFormEscapeRuntime({
  windowTarget,
  getFormRoot,
  requestClose,
}: HabitFormEscapeRuntimeDeps): () => void {
  if (!windowTarget) return () => {};

  const handler = (event: KeyboardEvent) => {
    if (!shouldRequestHabitFormCloseFromEscape({
      defaultPrevented: event.defaultPrevented,
      key: event.key,
      isComposing: event.isComposing,
      target: event.target,
      formRoot: getFormRoot(),
    })) return;
    event.preventDefault();
    void requestClose();
  };

  windowTarget.addEventListener('keydown', handler);
  return () => windowTarget.removeEventListener('keydown', handler);
}
