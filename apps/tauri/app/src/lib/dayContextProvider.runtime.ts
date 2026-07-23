import {
  createMidnightRolloverController,
  type MidnightRolloverHost,
} from './midnightRolloverController';

interface DayContextRolloverRuntimeDeps {
  host: MidnightRolloverHost;
  documentTarget: Pick<Document, 'addEventListener' | 'removeEventListener' | 'visibilityState'> | undefined;
  windowTarget: Pick<Window, 'addEventListener' | 'removeEventListener'> | undefined;
}

export function shouldHandleDayContextVisibilityWake(
  visibilityState: DocumentVisibilityState | undefined,
): boolean {
  return visibilityState === 'visible';
}

function createBrowserMidnightRolloverHost(
  options: Pick<MidnightRolloverHost, 'getCurrentYmd' | 'getDelayMs' | 'onRollover'>,
): MidnightRolloverHost {
  return {
    getCurrentYmd: options.getCurrentYmd,
    getDelayMs: options.getDelayMs,
    onRollover: options.onRollover,
    setTimeout: (callback, delayMs) => {
      const timer = globalThis.setTimeout(callback, delayMs);
      return () => {
        globalThis.clearTimeout(timer as ReturnType<typeof globalThis.setTimeout>);
      };
    },
  };
}

export function createBrowserDayContextRolloverRuntimeDeps(
  options: Pick<MidnightRolloverHost, 'getCurrentYmd' | 'getDelayMs' | 'onRollover'>,
): DayContextRolloverRuntimeDeps {
  return {
    host: createBrowserMidnightRolloverHost(options),
    documentTarget: typeof document === 'undefined' ? undefined : document,
    windowTarget: typeof window === 'undefined' ? undefined : window,
  };
}

export function startDayContextRolloverRuntime(
  deps: DayContextRolloverRuntimeDeps,
): () => void {
  const controller = createMidnightRolloverController(deps.host);
  const onVisibility = () => {
    if (shouldHandleDayContextVisibilityWake(deps.documentTarget?.visibilityState)) {
      controller.handleWake();
    }
  };
  const onFocus = () => {
    controller.handleWake();
  };

  deps.documentTarget?.addEventListener('visibilitychange', onVisibility);
  deps.windowTarget?.addEventListener('focus', onFocus);
  controller.mount();

  return () => {
    controller.dispose();
    deps.documentTarget?.removeEventListener('visibilitychange', onVisibility);
    deps.windowTarget?.removeEventListener('focus', onFocus);
  };
}
