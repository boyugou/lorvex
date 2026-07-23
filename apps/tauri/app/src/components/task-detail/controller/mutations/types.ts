import type { Dispatch, RefObject, SetStateAction } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import type { TaskUpdatePatch } from '@/lib/ipc/tasks/mutations/types';
import type { TranslationKey } from '@/lib/i18n';
import type { TranslationVars } from '@/locales';

export interface UseTaskDetailMutationDeps {
  invalidateAll: (options?: { extraListIds?: string[] }) => void;
  mountedRef: RefObject<boolean>;
  onClose: () => void;
  persistDraftsRef: RefObject<() => Promise<boolean>>;
  task: Task | null;
  t: (key: TranslationKey) => string;
  format: (key: TranslationKey, vars?: TranslationVars) => string;
}

export interface UseTaskDetailLifecycleMutationDeps
  extends UseTaskDetailMutationDeps {
  isCompleting: boolean;
  setIsCompleting: Dispatch<SetStateAction<boolean>>;
}

export interface TaskDetailMutationState {
  actionPending: boolean;
  handleComplete: () => Promise<void>;
  handleDelete: (cancelSeries?: boolean) => Promise<void>;
  handleDuplicate: () => Promise<void>;
  handlePermanentDelete: () => Promise<void>;
  handleReopen: () => Promise<void>;
  handleResetDeferral: () => Promise<void>;
  handleDefer: (untilDate: string | null, onSettled?: () => void) => Promise<void>;
  isCompleting: boolean;
  saveMetaPatch: (patch: TaskUpdatePatch) => Promise<boolean>;
}
