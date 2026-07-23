interface TauriRuntimeGlobal {
  __TAURI_INTERNALS__?: {
    invoke?: unknown;
    metadata?: unknown;
  };
}

export function isTauriRuntimeAvailable(): boolean {
  const runtime = globalThis as TauriRuntimeGlobal;
  return (
    typeof runtime.__TAURI_INTERNALS__?.invoke === 'function'
    && runtime.__TAURI_INTERNALS__.metadata !== undefined
  );
}
