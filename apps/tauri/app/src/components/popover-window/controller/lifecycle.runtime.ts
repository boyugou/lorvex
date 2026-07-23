type PopoverPendingHideTimerHandle = ReturnType<typeof globalThis.setTimeout>;

export interface PopoverPendingHideTimerHost {
  clearTimeout: (handle: PopoverPendingHideTimerHandle) => void;
  setTimeout: (
    callback: () => void,
    delayMs: number,
  ) => PopoverPendingHideTimerHandle;
}

export function createBrowserPopoverPendingHideTimerHost(): PopoverPendingHideTimerHost {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

export interface PopoverPendingHideTimerRef {
  current: PopoverPendingHideTimerHandle | null;
}

export function clearPopoverPendingHideTimer(
  pendingHideTimerRef: PopoverPendingHideTimerRef,
  timerHost: Pick<PopoverPendingHideTimerHost, 'clearTimeout'>,
): void {
  if (pendingHideTimerRef.current === null) {
    return;
  }
  timerHost.clearTimeout(pendingHideTimerRef.current);
  pendingHideTimerRef.current = null;
}

export function schedulePopoverPendingHide(
  pendingHideTimerRef: PopoverPendingHideTimerRef,
  timerHost: PopoverPendingHideTimerHost,
  delayMs: number,
  callback: () => void,
): void {
  clearPopoverPendingHideTimer(pendingHideTimerRef, timerHost);
  pendingHideTimerRef.current = timerHost.setTimeout(() => {
    pendingHideTimerRef.current = null;
    callback();
  }, delayMs);
}
