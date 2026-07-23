export interface CompactToolbarFocusTimerHost {
  setTimeout: (callback: () => void, delayMs: number) => unknown;
}

export function createBrowserCompactToolbarFocusTimerHost(): CompactToolbarFocusTimerHost {
  return {
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

export function deferCompactToolbarFocus(
  timerHost: CompactToolbarFocusTimerHost,
  focus: () => void,
): void {
  timerHost.setTimeout(focus, 0);
}
