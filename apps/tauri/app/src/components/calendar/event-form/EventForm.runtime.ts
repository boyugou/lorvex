type EventFormKeydownTarget = Pick<Document, 'addEventListener' | 'removeEventListener'>;

interface EventFormEscapeRuntimeDeps {
  documentTarget?: EventFormKeydownTarget | undefined;
  getFormRoot: () => HTMLElement | null;
  getOnCancel: () => () => void;
}

export function shouldCancelEventFormFromKey(
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

export function installEventFormEscapeRuntime({
  documentTarget,
  getFormRoot,
  getOnCancel,
}: EventFormEscapeRuntimeDeps): () => void {
  if (!documentTarget) return () => {};

  const handleKeyDown = (event: KeyboardEvent) => {
    if (!shouldCancelEventFormFromKey({
      defaultPrevented: event.defaultPrevented,
      key: event.key,
      isComposing: event.isComposing,
      target: event.target,
      formRoot: getFormRoot(),
    })) return;
    event.preventDefault();
    getOnCancel()();
  };

  documentTarget.addEventListener('keydown', handleKeyDown);
  return () => documentTarget.removeEventListener('keydown', handleKeyDown);
}
