import { DRAFT_KEYS } from '@/lib/storage/drafts';

export const QUICK_CAPTURE_DRAFT_STORAGE_KEY = DRAFT_KEYS.quickCapture;

export interface QuickCaptureDraftAutosaveSnapshot {
  body: string;
  selectedListId: string | null;
  tagsInput: string;
  title: string;
}

interface QuickCaptureDraftAutosaveTickDeps {
  clearDraft: () => void;
  persistDraft: (serializedDraft: string) => void;
  reportPersistError: (error: unknown) => void;
  snapshot: QuickCaptureDraftAutosaveSnapshot;
}

export interface QuickCaptureDraftAutosaveRuntimeDeps
  extends QuickCaptureDraftAutosaveTickDeps {
  clearTimeout: (handle: unknown) => void;
  delayMs: number;
  setTimeout: (callback: () => void, delayMs: number) => unknown;
}

export function hasQuickCaptureDraftContent(
  snapshot: Pick<QuickCaptureDraftAutosaveSnapshot, 'body' | 'tagsInput' | 'title'>,
): boolean {
  return Boolean(snapshot.title.trim() || snapshot.body.trim() || snapshot.tagsInput.trim());
}

export function runQuickCaptureDraftAutosaveTick(
  deps: QuickCaptureDraftAutosaveTickDeps,
): void {
  if (!hasQuickCaptureDraftContent(deps.snapshot)) {
    try {
      deps.clearDraft();
    } catch {
      // Best-effort cleanup: failing to remove an empty recovery draft is non-fatal.
    }
    return;
  }

  try {
    deps.persistDraft(JSON.stringify(deps.snapshot));
  } catch (error) {
    deps.reportPersistError(error);
  }
}

export function createBrowserQuickCaptureDraftAutosaveTimerHost(): Pick<
  QuickCaptureDraftAutosaveRuntimeDeps,
  'clearTimeout' | 'setTimeout'
> {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

export function installQuickCaptureDraftAutosaveRuntime(
  deps: QuickCaptureDraftAutosaveRuntimeDeps,
): () => void {
  const handle = deps.setTimeout(() => {
    runQuickCaptureDraftAutosaveTick(deps);
  }, deps.delayMs);

  return () => {
    deps.clearTimeout(handle);
  };
}
