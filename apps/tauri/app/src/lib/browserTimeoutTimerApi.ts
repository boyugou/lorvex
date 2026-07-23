interface BrowserTimeoutTimerApi {
  clear: (handle: unknown) => void;
  schedule: (callback: () => void, delayMs: number) => unknown;
}

interface BrowserCancelableTimeoutTimerApi {
  cancel: (handle: unknown) => void;
  schedule: (callback: () => void, delayMs: number) => unknown;
}

export function createBrowserTimeoutTimerApi(): BrowserTimeoutTimerApi {
  return {
    clear: clearBrowserTimeout,
    schedule: scheduleBrowserTimeout,
  };
}

export function createBrowserCancelableTimeoutTimerApi(): BrowserCancelableTimeoutTimerApi {
  return {
    cancel: clearBrowserTimeout,
    schedule: scheduleBrowserTimeout,
  };
}

function clearBrowserTimeout(handle: unknown): void {
  clearTimeout(handle as ReturnType<typeof setTimeout>);
}

function scheduleBrowserTimeout(callback: () => void, delayMs: number): unknown {
  return setTimeout(callback, delayMs);
}
