import type { PersistedDailyReviewDraft } from './draft.logic';

interface DailyReviewDraftAutosaveTimerHost {
  clearTimeout: (handle: unknown) => void;
  setTimeout: (callback: () => void, delayMs: number) => unknown;
}

interface DailyReviewDraftAutosaveTickDeps {
  draft: PersistedDailyReviewDraft;
  persistSerializedDraft: (serializedDraft: string) => void;
  reportPersistError: (error: unknown) => void;
  serializeDraft: (draft: PersistedDailyReviewDraft) => string;
}

interface DailyReviewDraftAutosaveRuntimeDeps
  extends DailyReviewDraftAutosaveTickDeps {
  delayMs: number;
  timerHost: DailyReviewDraftAutosaveTimerHost;
}

export function runDailyReviewDraftAutosaveTick({
  draft,
  persistSerializedDraft,
  reportPersistError,
  serializeDraft,
}: DailyReviewDraftAutosaveTickDeps): void {
  try {
    persistSerializedDraft(serializeDraft(draft));
  } catch (error) {
    reportPersistError(error);
  }
}

export function installDailyReviewDraftAutosaveRuntime(
  deps: DailyReviewDraftAutosaveRuntimeDeps,
): () => void {
  const handle = deps.timerHost.setTimeout(() => {
    runDailyReviewDraftAutosaveTick(deps);
  }, deps.delayMs);

  return () => {
    deps.timerHost.clearTimeout(handle);
  };
}
