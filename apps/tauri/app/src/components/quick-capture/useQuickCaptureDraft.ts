import { useEffect } from 'react';

import { reportClientError } from '@/lib/errors/errorLogging';
import type { ListWithCount } from '@/lib/ipc/tasks/models';
import { clearDraft, readDraft, writeDraft } from '@/lib/storage/drafts';
import { getUIStateString, removeUIState, setUIState } from '@/lib/storage/uiState';

import {
  createBrowserQuickCaptureDraftAutosaveTimerHost,
  installQuickCaptureDraftAutosaveRuntime,
  QUICK_CAPTURE_DRAFT_STORAGE_KEY,
} from './quickCaptureDraftAutosave.runtime';
import {
  type QuickCaptureDraft,
  readQuickCaptureDraftFromStorageValue,
  restoreLastListIdFromValue,
} from './useQuickCaptureForm.logic';

const quickCaptureDraftAutosaveTimerHost = createBrowserQuickCaptureDraftAutosaveTimerHost();

export function restoreQuickCaptureLastListId(lists: ListWithCount[]): string | null {
  return restoreLastListIdFromValue(lists, getUIStateString('quickCapture:lastListId', ''));
}

/// durability: debounced draft persistence so a hard
// crash/force-quit between keystroke and Enter doesn't lose typed
// content. Kept minimal — title + body + tags + list are the only
// fields expensive to retype; dateOption/priority/duration are
// cheaper click choices and not worth the storage churn.
export function readQuickCaptureDraft(): QuickCaptureDraft | null {
  return readQuickCaptureDraftFromStorageValue(readDraft(QUICK_CAPTURE_DRAFT_STORAGE_KEY));
}

export function clearQuickCaptureDraft(): void {
  clearDraft(QUICK_CAPTURE_DRAFT_STORAGE_KEY);
}

export function persistQuickCaptureListId(listId: string | null): void {
  if (listId) {
    setUIState('quickCapture:lastListId', listId);
  } else {
    removeUIState('quickCapture:lastListId');
  }
}

interface UseQuickCaptureDraftAutosaveArgs {
  title: string;
  body: string;
  tagsInput: string;
  selectedListId: string | null;
}

export function useQuickCaptureDraftAutosave({
  title,
  body,
  tagsInput,
  selectedListId,
}: UseQuickCaptureDraftAutosaveArgs): void {
  useEffect(() => {
    return installQuickCaptureDraftAutosaveRuntime({
      clearDraft: clearQuickCaptureDraft,
      delayMs: 500,
      persistDraft: (serializedDraft) => {
        writeDraft(QUICK_CAPTURE_DRAFT_STORAGE_KEY, serializedDraft);
      },
      reportPersistError: (err) => {
        reportClientError(
          'quickCapture.autosave.draft',
          'Failed to persist quick-capture draft',
          err,
          undefined,
          'warn',
        );
      },
      snapshot: { title, body, tagsInput, selectedListId },
      ...quickCaptureDraftAutosaveTimerHost,
    });
  }, [title, body, tagsInput, selectedListId]);
}
