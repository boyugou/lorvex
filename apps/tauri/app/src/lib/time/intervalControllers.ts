export interface IntervalHost {
  runTick: () => void;
  setInterval: (callback: () => void, delayMs: number) => () => void;
}

export interface VisibilityIntervalHost extends IntervalHost {
  isVisible: () => boolean;
}

interface IntervalController {
  dispose: () => void;
  hasActiveTimer: () => boolean;
  mount: () => void;
}

interface VisibilityIntervalController extends IntervalController {
  handleVisibilityChange: () => void;
}

export function createVisibilityGatedIntervalController(
  host: VisibilityIntervalHost,
  intervalMs: number,
): VisibilityIntervalController {
  let cancelTimer: (() => void) | null = null;

  const start = () => {
    if (cancelTimer) return;
    host.runTick();
    cancelTimer = host.setInterval(() => host.runTick(), intervalMs);
  };

  const stop = () => {
    cancelTimer?.();
    cancelTimer = null;
  };

  const syncToVisibility = () => {
    if (host.isVisible()) {
      start();
    } else {
      stop();
    }
  };

  return {
    mount: syncToVisibility,
    handleVisibilityChange: syncToVisibility,
    dispose: stop,
    hasActiveTimer: () => cancelTimer !== null,
  };
}
