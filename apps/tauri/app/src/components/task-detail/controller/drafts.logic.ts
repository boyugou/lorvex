export interface ReconcileTaskDraftFieldArgs {
  dirty: boolean;
  currentDraft: string;
  incomingValue: string;
  skipValue: string | null | undefined;
}

export interface ReconcileTaskDraftFieldResult {
  nextDraft: string;
  nextSkipValue: string | null;
  shouldUpdateDraft: boolean;
}

export function shouldPersistTaskDetailDrafts(args: {
  bodyDirty: boolean;
  titleDirty: boolean;
}): boolean {
  return args.bodyDirty || args.titleDirty;
}

export function reconcileTaskDraftField({
  dirty,
  currentDraft,
  incomingValue,
  skipValue,
}: ReconcileTaskDraftFieldArgs): ReconcileTaskDraftFieldResult {
  if (dirty) {
    return {
      nextDraft: currentDraft,
      nextSkipValue: skipValue ?? null,
      shouldUpdateDraft: false,
    };
  }

  if (skipValue != null && incomingValue === skipValue) {
    return {
      nextDraft: currentDraft,
      nextSkipValue: null,
      shouldUpdateDraft: false,
    };
  }

  return {
    nextDraft: incomingValue,
    nextSkipValue: null,
    shouldUpdateDraft: incomingValue !== currentDraft,
  };
}
