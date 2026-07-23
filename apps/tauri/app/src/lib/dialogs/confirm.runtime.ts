export function readActiveConfirmTriggerElement(): HTMLElement | null {
  try {
    const activeElement = globalThis.document?.activeElement;
    const elementConstructor = globalThis.HTMLElement;
    return activeElement instanceof elementConstructor ? activeElement : null;
  } catch {
    return null;
  }
}
