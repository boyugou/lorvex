interface DangerZoneLinkRuntimeState {
  focusTimer: unknown | null;
}

export interface DangerZoneLinkTimerHost {
  clearTimeout: (handle: unknown) => void;
  setTimeout: (callback: () => void, delayMs: number) => unknown;
}

interface DangerZoneLinkFocusTarget {
  querySelector: <ElementType extends Element = Element>(selectors: string) => ElementType | null;
  scrollIntoView: (arg?: boolean | ScrollIntoViewOptions) => void;
}

interface ScheduleDangerZoneLinkFocusDeps {
  delayMs: number;
  state: DangerZoneLinkRuntimeState;
  target: DangerZoneLinkFocusTarget;
  timerHost: DangerZoneLinkTimerHost;
}

export function createDangerZoneLinkRuntimeState(): DangerZoneLinkRuntimeState {
  return { focusTimer: null };
}

export function createBrowserDangerZoneLinkTimerHost(): DangerZoneLinkTimerHost {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

export function cleanupDangerZoneLinkFocus(
  state: DangerZoneLinkRuntimeState,
  timerHost: Pick<DangerZoneLinkTimerHost, 'clearTimeout'>,
): void {
  if (state.focusTimer === null) return;
  timerHost.clearTimeout(state.focusTimer);
  state.focusTimer = null;
}

export function scheduleDangerZoneLinkFocus({
  delayMs,
  state,
  target,
  timerHost,
}: ScheduleDangerZoneLinkFocusDeps): void {
  cleanupDangerZoneLinkFocus(state, timerHost);
  target.scrollIntoView({ behavior: 'smooth', block: 'start' });
  state.focusTimer = timerHost.setTimeout(() => {
    state.focusTimer = null;
    const heading = target.querySelector<HTMLElement>('h2');
    heading?.focus({ preventScroll: true });
  }, delayMs);
}
