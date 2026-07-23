interface IpcMutationBroadcastPayload {
  command: string;
  mutated_at: string;
  source_window: string;
}

interface IpcMutationSideEffectDeps {
  command: string;
  broadcastMutation: (payload: IpcMutationBroadcastPayload) => Promise<unknown>;
  getCurrentWindowLabel: () => string;
  nowIso?: () => string;
}

interface InvokeIpcRuntimeDeps<T> {
  invoke: () => Promise<T>;
  runSideEffects: () => void;
}

export function invokeWithAbortRuntime<T>({
  invoke,
  signal,
}: {
  invoke: () => Promise<T>;
  signal?: AbortSignal;
}): Promise<T> {
  if (!signal) {
    return invoke();
  }
  if (signal.aborted) {
    return Promise.reject(
      new DOMException('IPC call aborted before dispatch', 'AbortError'),
    );
  }
  const inner = invoke();
  return new Promise<T>((resolve, reject) => {
    const onAbort = () => {
      signal.removeEventListener('abort', onAbort);
      reject(new DOMException('IPC call aborted', 'AbortError'));
    };
    signal.addEventListener('abort', onAbort);
    inner.then(
      (value) => {
        signal.removeEventListener('abort', onAbort);
        resolve(value);
      },
      (error) => {
        signal.removeEventListener('abort', onAbort);
        reject(error);
      },
    );
  });
}

export function resolveIpcMutationSourceWindow(getCurrentWindowLabel: () => string): string {
  try {
    return getCurrentWindowLabel();
  } catch {
    return '';
  }
}

export function buildIpcMutationBroadcastPayload(args: {
  command: string;
  sourceWindow: string;
  nowIso?: () => string;
}): IpcMutationBroadcastPayload {
  return {
    command: args.command,
    mutated_at: (args.nowIso ?? (() => new Date().toISOString()))(),
    source_window: args.sourceWindow,
  };
}

export function runIpcMutationSideEffectsRuntime(
  deps: IpcMutationSideEffectDeps,
): void {
  const sourceWindow = resolveIpcMutationSourceWindow(deps.getCurrentWindowLabel);
  const payload = deps.nowIso
    ? buildIpcMutationBroadcastPayload({
      command: deps.command,
      sourceWindow,
      nowIso: deps.nowIso,
    })
    : buildIpcMutationBroadcastPayload({
      command: deps.command,
      sourceWindow,
    });

  void deps.broadcastMutation(payload).catch(() => {
    // Best-effort broadcast — silently ignore failures.
  });

}

export async function invokeIpcRuntime<T>({
  invoke,
  runSideEffects,
}: InvokeIpcRuntimeDeps<T>): Promise<T> {
  const result = await invoke();
  runSideEffects();
  return result;
}
