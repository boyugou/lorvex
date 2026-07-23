const handledEscapeEvents = new WeakSet<object>();

export function markEscapeEventHandled(event: object): void {
  handledEscapeEvents.add(event);
}

export function isEscapeEventHandled(event: object | null | undefined): boolean {
  return typeof event === 'object' && event !== null && handledEscapeEvents.has(event);
}
