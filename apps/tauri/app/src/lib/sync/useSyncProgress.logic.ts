import { createAsyncTauriListenerScope } from '../tauriListenerLifecycle';
import { hasOnlyKeys, isPlainRecord as isRecord } from '../objectGuards';

export const SYNC_PROGRESS_EVENT = 'lorvex://sync/progress';

type SyncProgressPhase = 'push' | 'pull' | 'apply' | 'idle';

export interface SyncProgressPayload {
  phase: SyncProgressPhase;
  current: number;
  total: number;
  cycle_id: string;
}

export interface SyncProgressState {
  cycleId: string | null;
  phase: SyncProgressPhase;
  current: number;
  total: number;
  determinate: boolean;
}

export const IDLE_SYNC_PROGRESS_STATE: SyncProgressState = {
  cycleId: null,
  phase: 'idle',
  current: 0,
  total: 0,
  determinate: false,
};

export function reduceSyncProgress(
  previous: SyncProgressState,
  payload: SyncProgressPayload,
): SyncProgressState {
  const previousId = previous.cycleId;

  if (payload.phase === 'idle') {
    if (previousId && previousId !== payload.cycle_id) {
      return previous;
    }
    return IDLE_SYNC_PROGRESS_STATE;
  }

  if (previousId && previousId !== payload.cycle_id) {
    return previous;
  }

  const determinate = payload.total > 0;
  return {
    cycleId: payload.cycle_id,
    phase: payload.phase,
    current: payload.current,
    total: payload.total,
    determinate,
  };
}

interface SyncProgressEvent<T> {
  payload: T;
}

type SyncProgressUnlisten = () => void;

interface SyncProgressSubscriptionDeps {
  listen: (
    event: string,
    handler: (event: SyncProgressEvent<SyncProgressPayload>) => void,
  ) => Promise<SyncProgressUnlisten>;
  setState: (updater: (previous: SyncProgressState) => SyncProgressState) => void;
  reportError: (error: unknown) => void;
}

const SYNC_PROGRESS_PHASES: ReadonlySet<SyncProgressPhase> = new Set([
  'push',
  'pull',
  'apply',
  'idle',
]);

const SYNC_PROGRESS_PAYLOAD_KEYS = new Set(['cycle_id', 'current', 'phase', 'total']);

function hasOnlySyncProgressPayloadKeys(value: Record<string, unknown>): boolean {
  return hasOnlyKeys(value, SYNC_PROGRESS_PAYLOAD_KEYS);
}

export function normalizeSyncProgressPayload(value: unknown): SyncProgressPayload | null {
  if (!isRecord(value) || !hasOnlySyncProgressPayloadKeys(value)) {
    return null;
  }
  const record = value;
  if (
    typeof record.cycle_id !== 'string' ||
    record.cycle_id.trim().length === 0 ||
    record.cycle_id !== record.cycle_id.trim() ||
    typeof record.current !== 'number' ||
    !Number.isFinite(record.current) ||
    !Number.isInteger(record.current) ||
    record.current < 0 ||
    typeof record.total !== 'number' ||
    !Number.isFinite(record.total) ||
    !Number.isInteger(record.total) ||
    record.total < 0 ||
    (record.total > 0 && record.current > record.total) ||
    typeof record.phase !== 'string' ||
    !SYNC_PROGRESS_PHASES.has(record.phase as SyncProgressPhase)
  ) {
    return null;
  }
  return {
    cycle_id: record.cycle_id,
    current: record.current,
    total: record.total,
    phase: record.phase as SyncProgressPhase,
  };
}

export function startSyncProgressSubscription(
  deps: SyncProgressSubscriptionDeps,
): SyncProgressUnlisten {
  const listeners = createAsyncTauriListenerScope();

  listeners.add(
    deps.listen(SYNC_PROGRESS_EVENT, (event) => {
      const payload = normalizeSyncProgressPayload(event.payload);
      if (!payload) {
        return;
      }
      deps.setState((previous) => reduceSyncProgress(previous, payload));
    }),
    (error) => {
      deps.reportError(error);
    },
  );

  return () => {
    listeners.dispose();
  };
}
