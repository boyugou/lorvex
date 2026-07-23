import { invoke as tauriInvoke } from '@tauri-apps/api/core';
import { emit } from '@tauri-apps/api/event';
import { getCurrentWebviewWindow } from '@tauri-apps/api/webviewWindow';

import { normalizeInvokePayload } from './core.logic';
import {
  invokeIpcRuntime,
  invokeWithAbortRuntime,
  runIpcMutationSideEffectsRuntime,
} from './core.runtime';

export const IPC_MUTATION_BROADCAST_EVENT = 'ipc://mutation';

/**
 * Invoke a Tauri command with optional AbortSignal-aware cancellation.
 *
 * Tauri 2.x cannot literally cancel a running Rust command — the backend
 * always runs to completion. However, TanStack Query v5 passes an
 * `AbortSignal` to every `queryFn` and relies on the returned promise
 * rejecting with an `AbortError` when the query unmounts mid-flight, so
 * the (now stale) result is discarded instead of written back into the
 * cache.
 *
 * When a signal is supplied we race the underlying invoke promise against
 * the signal's `abort` event: if the caller aborts first, the returned
 * promise rejects with a DOMException('AbortError') and TanStack drops
 * the result on the floor. The Rust command still runs to completion on
 * the backend — we just don't let its result poison a stale cache entry.
 */
export function invoke<T>(
  command: string,
  payload?: Record<string, unknown>,
  signal?: AbortSignal,
): Promise<T> {
  return signal
    ? invokeWithAbortRuntime({
      invoke: () => tauriInvoke<T>(command, normalizeInvokePayload(payload)),
      signal,
    })
    : invokeWithAbortRuntime({
      invoke: () => tauriInvoke<T>(command, normalizeInvokePayload(payload)),
    });
}

function runIpcMutationSideEffects(command: string): void {
  runIpcMutationSideEffectsRuntime({
    command,
    broadcastMutation: (payload) => emit(IPC_MUTATION_BROADCAST_EVENT, payload),
    getCurrentWindowLabel: () => getCurrentWebviewWindow().label,
  });
}

export async function invokeIpc<T>(
  command: string,
  payload?: Record<string, unknown>,
  signal?: AbortSignal,
): Promise<T> {
  return invokeIpcRuntime({
    invoke: () => invoke<T>(command, payload, signal),
    runSideEffects: () => {
      runIpcMutationSideEffects(command);
    },
  });
}

export { toIpcErrorMessage, toUserFacingErrorMessage } from './core.logic';
