import type { RecentUndoToken } from '@/lib/undoTokenStore';

export interface RecentUndoTokenIntervalHost {
  clearInterval: (handle: unknown) => void;
  setInterval: (callback: () => void, delayMs: number) => unknown;
}

export function createBrowserRecentUndoTokenIntervalHost(): RecentUndoTokenIntervalHost | null {
  if (typeof window === 'undefined') {
    return null;
  }
  return {
    clearInterval: (handle) => {
      globalThis.clearInterval(handle as ReturnType<typeof globalThis.setInterval>);
    },
    setInterval: (callback, delayMs) => globalThis.setInterval(callback, delayMs),
  };
}

interface InstallRecentUndoTokenSnapshotRuntimeDeps {
  intervalHost: RecentUndoTokenIntervalHost | null;
  intervalMs: number;
  publishTokens: (tokens: RecentUndoToken[]) => void;
  snapshotTokens: () => RecentUndoToken[];
}

export function installRecentUndoTokenSnapshotRuntime({
  intervalHost,
  intervalMs,
  publishTokens,
  snapshotTokens,
}: InstallRecentUndoTokenSnapshotRuntimeDeps): () => void {
  const publishSnapshot = () => {
    publishTokens(snapshotTokens());
  };

  publishSnapshot();

  if (!intervalHost) {
    return () => {};
  }

  const handle = intervalHost.setInterval(publishSnapshot, intervalMs);
  return () => {
    intervalHost.clearInterval(handle);
  };
}
