import {
  createMemoryEntry,
  deleteAiMemoryEntry,
  deleteNotesForAi,
  restoreMemoryRevision,
  setNotesForAi,
} from '@/lib/ipc/memory';
import type { TranslationKey } from '@/lib/i18n';
import { defineEntityHooks } from '@/lib/query/defineEntityHooks';
import { QUERY_KEYS } from '@/lib/query/queryKeyFactory';
import { getAiMemory } from '@/lib/ipc/memory';

const memoryHooks = defineEntityHooks({
  entity: 'memory',
  queries: {
    all: {
      key: () => QUERY_KEYS.aiMemory(),
      fetch: (signal?: AbortSignal) => getAiMemory(signal),
    },
  },
  mutations: {
    forget: {
      run: (key: string) => deleteAiMemoryEntry(key),
      errorContext: 'memory_forget_entry',
    },
    create: {
      run: (input: { key: string; content: string }) =>
        createMemoryEntry(input.key, input.content),
      errorContext: 'memory_create_entry',
    },
    saveNotes: {
      run: (content: string) => setNotesForAi(content),
      errorContext: 'memory_save_notes',
    },
    deleteNotes: {
      run: (_: void) => deleteNotesForAi(),
      errorContext: 'memory_delete_notes',
    },
    restoreRevision: {
      run: (revisionId: string) => restoreMemoryRevision(revisionId),
      errorContext: 'memory_restore_revision',
    },
  },
});

interface UseAiMemoryActionsArgs {
  onSuccess?: () => void;
  t: (key: TranslationKey) => string;
}

export function useForgetMemoryEntryAction({ onSuccess, t }: UseAiMemoryActionsArgs) {
  return memoryHooks.mutations.forget.useMutation({
    successMessage: t('memory.entryForgotten'),
    errorMessage: t('common.error'),
    onSuccess: () => onSuccess?.(),
  });
}

export function useCreateMemoryEntryAction({
  onSuccess,
  t,
  onCreated,
}: UseAiMemoryActionsArgs & {
  onCreated?: () => void;
}) {
  return memoryHooks.mutations.create.useMutation({
    successMessage: t('memory.entryCreated'),
    errorMessage: t('common.error'),
    onSuccess: () => {
      onCreated?.();
      onSuccess?.();
    },
  });
}

export function useNotesForAiActions({
  onSuccess,
  t,
  onSaved,
}: UseAiMemoryActionsArgs & {
  onSaved: () => void;
}) {
  const saveMutation = memoryHooks.mutations.saveNotes.useMutation({
    successMessage: t('memory.notesUpdated'),
    errorMessage: t('common.error'),
    onSuccess: () => {
      onSaved();
      onSuccess?.();
    },
  });
  const deleteMutation = memoryHooks.mutations.deleteNotes.useMutation({
    successMessage: t('memory.notesDeleted'),
    errorMessage: t('common.error'),
    onSuccess: () => onSuccess?.(),
  });
  return { saveMutation, deleteMutation };
}

export function useRestoreMemoryRevisionAction({
  onSuccess,
  t,
}: UseAiMemoryActionsArgs) {
  // Override invalidation to `memory_revision` (covers `aiMemory` +
  // `memoryHistory`) so the history modal refreshes alongside the
  // canonical memory list.
  return memoryHooks.mutations.restoreRevision.useMutation({
    successMessage: t('memory.revisionRestored'),
    errorMessage: t('common.error'),
    invalidateEntity: 'memory_revision',
    onSuccess: () => onSuccess?.(),
  });
}
