import { createBrowserTimeoutTimerApi } from './browserTimeoutTimerApi';

export interface TimerApi {
  clear(handle: unknown): void;
  schedule(cb: () => void, delayMs: number): unknown;
}

interface EntityInvalidationCoalescer {
  clear(): void;
  schedule(entity: string): void;
}

const defaultTimerApi: TimerApi = createBrowserTimeoutTimerApi();

export function shouldIgnoreMutationBroadcast(
  ownLabel: string,
  sourceWindow: string | undefined,
): boolean {
  return ownLabel.length > 0 && sourceWindow === ownLabel;
}

export function createEntityInvalidationCoalescer(
  invalidateEntity: (entity: string) => void,
  delayMs: number,
  timerApi: TimerApi = defaultTimerApi,
): EntityInvalidationCoalescer {
  const pendingTimers = new Map<string, unknown>();

  return {
    schedule(entity) {
      const existing = pendingTimers.get(entity);
      if (existing !== undefined) {
        timerApi.clear(existing);
      }
      const handle = timerApi.schedule(() => {
        pendingTimers.delete(entity);
        invalidateEntity(entity);
      }, delayMs);
      pendingTimers.set(entity, handle);
    },

    clear() {
      for (const handle of pendingTimers.values()) {
        timerApi.clear(handle);
      }
      pendingTimers.clear();
    },
  };
}
