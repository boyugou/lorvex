export interface MidnightRolloverHost {
  getCurrentYmd: () => string;
  getDelayMs: () => number;
  onRollover: () => void;
  setTimeout: (callback: () => void, delayMs: number) => () => void;
}

interface MidnightRolloverController {
  dispose: () => void;
  handleWake: () => void;
  hasActiveTimer: () => boolean;
  mount: () => void;
}

export function createMidnightRolloverController(
  host: MidnightRolloverHost,
): MidnightRolloverController {
  let cancelTimer: (() => void) | null = null;
  let disposed = false;
  let expectedYmd = host.getCurrentYmd();

  const stop = () => {
    cancelTimer?.();
    cancelTimer = null;
  };

  const arm = () => {
    if (disposed) return;
    stop();
    expectedYmd = host.getCurrentYmd();
    cancelTimer = host.setTimeout(() => {
      if (disposed) return;
      host.onRollover();
      arm();
    }, host.getDelayMs());
  };

  return {
    mount: arm,
    handleWake: () => {
      if (disposed) return;
      if (host.getCurrentYmd() === expectedYmd) return;
      host.onRollover();
      arm();
    },
    dispose: () => {
      disposed = true;
      stop();
    },
    hasActiveTimer: () => cancelTimer !== null,
  };
}
