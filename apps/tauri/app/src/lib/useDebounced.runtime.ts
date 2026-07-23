export interface DebounceTimerHost {
  clearTimeout: (handle: unknown) => void;
  setTimeout: (callback: () => void, delayMs: number) => unknown;
}

export function createBrowserDebounceTimerHost(): DebounceTimerHost {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

export function scheduleDebouncedUpdate(
  host: DebounceTimerHost,
  update: () => void,
  delayMs: number,
): () => void {
  const handle = host.setTimeout(update, delayMs);
  return () => host.clearTimeout(handle);
}
