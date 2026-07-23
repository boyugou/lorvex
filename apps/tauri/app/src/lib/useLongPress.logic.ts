import { createBrowserTimeoutTimerApi } from './browserTimeoutTimerApi';

export const LONG_PRESS_MS = 500;
export const MOVE_THRESHOLD_PX = 10;

interface LongPressPoint {
  x: number;
  y: number;
}

export interface LongPressTimerApi {
  clear: (handle: unknown) => void;
  schedule: (callback: () => void, delayMs: number) => unknown;
}

interface LongPressController {
  dispose: () => void;
  end: () => void;
  hasPending: () => boolean;
  move: (point: LongPressPoint) => void;
  start: (point: LongPressPoint) => void;
}

const defaultTimerApi: LongPressTimerApi = createBrowserTimeoutTimerApi();

export function createLongPressController(
  onLongPress: (point: LongPressPoint) => void,
  timerApi: LongPressTimerApi = defaultTimerApi,
): LongPressController {
  let timerHandle: unknown = null;
  let startPoint: LongPressPoint | null = null;
  let pressPoint: LongPressPoint | null = null;

  const clearPending = () => {
    if (timerHandle !== null) {
      timerApi.clear(timerHandle);
      timerHandle = null;
    }
  };

  return {
    start: (point) => {
      startPoint = point;
      pressPoint = point;
      clearPending();
      timerHandle = timerApi.schedule(() => {
        timerHandle = null;
        if (pressPoint) {
          onLongPress(pressPoint);
        }
      }, LONG_PRESS_MS);
    },
    move: (point) => {
      if (!startPoint) return;
      const dx = Math.abs(point.x - startPoint.x);
      const dy = Math.abs(point.y - startPoint.y);
      if (dx > MOVE_THRESHOLD_PX || dy > MOVE_THRESHOLD_PX) {
        clearPending();
      }
    },
    end: () => {
      clearPending();
      startPoint = null;
      pressPoint = null;
    },
    dispose: () => {
      clearPending();
      startPoint = null;
      pressPoint = null;
    },
    hasPending: () => timerHandle !== null,
  };
}
