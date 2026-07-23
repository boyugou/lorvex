import type { CSSProperties, KeyboardEvent as ReactKeyboardEvent, MutableRefObject } from 'react';
import { toIpcErrorMessage } from '@/lib/ipc/core.logic';
import type { AttributionActor, Task, TaskAttribution } from '@/lib/ipc/tasks/models';
import type { TaskUpdatePatch } from '@/lib/ipc/tasks/mutations/types';
import { reportClientError } from '@/lib/errors/errorLogging';
import type { TranslationKey } from '@/lib/i18n';

export interface TaskDetailProps {
  taskId: string;
  onClose: () => void;
  onSelectTask?: ((id: string) => void) | undefined;
  isMobile?: boolean;
  /**
   * Optional out-ref the controller writes its `persistDrafts` callback into
   * so a parent surface (e.g. SlidePanel host) can flush in-flight drafts
   * before tearing the panel down via a parent-owned close path that does
   * not go through `onClose` (scrim click, X button, ErrorBoundary fallback).
   * Returns `true` if drafts persisted cleanly and the close should proceed,
   * `false` if a save error means the panel must stay open. When the panel
   * unmounts the ref is reset so callers can detect a missing handler.
   */
  flushDraftsRef?: MutableRefObject<(() => Promise<boolean>) | null> | undefined;
}

interface TaskDetailDepTaskView {
  status: string;
  title: string;
}

type Translator = (key: TranslationKey) => string;

export interface TaskDetailControllerState {
  actionPending: boolean;
  attribution: TaskAttribution | null;
  blocksIds: string[];
  bodyDraft: string;
  contentClass: string;
  dependsOnIds: string[];
  depTaskMap: Record<string, TaskDetailDepTaskView>;
  error: unknown;
  handleBodyDraftChange: (next: string) => void;
  handleBodyDirtyChange: (next: boolean) => void;
  handleClose: () => Promise<void>;
  handleComplete: () => Promise<void>;
  handleDelete: (cancelSeries?: boolean) => Promise<void>;
  handleDuplicate: () => Promise<void>;
  handlePermanentDelete: () => Promise<void>;
  handleReopen: () => Promise<void>;
  handleResetDeferral: () => Promise<void>;
  saveMetaPatch: (patch: TaskUpdatePatch) => Promise<boolean>;
  handleDefer: (untilDate: string | null) => Promise<void>;
  handleTitleBlur: () => void;
  handleTitleChange: (value: string) => void;
  handleTitleCompositionEnd: () => void;
  handleTitleCompositionStart: () => void;
  handleTitleKeyDown: (event: ReactKeyboardEvent<HTMLInputElement>) => void;
  headerClass: string;
  headerStyle: CSSProperties | undefined;
  isCompleting: boolean;
  isComplete: boolean;
  isLoading: boolean;
  isMobile: boolean;
  locale: string;
  onSelectTask?: ((id: string) => void) | undefined;
  overdue: boolean;
  persistBody: (draft?: string) => Promise<boolean>;
  refetchTask: () => Promise<unknown>;
  savingBody: boolean;
  savingTitle: boolean;
  shellClass: string;
  statusLabel: string;
  t: Translator;
  task: Task | null;
  taskId: string;
  titleComposing: boolean;
  titleDraft: string;
  titleDirty: boolean;
  unsavedChanges: boolean;
}

/** Return the array directly, defaulting to [] if null. */
export function parseJsonIds(ids: string[] | null): string[] {
  return ids ?? [];
}

export function formatAttributionActor(
  actor: AttributionActor | null | undefined,
  t: Translator,
): string {
  if (!actor || actor.kind === 'human') return t('task.actor.human');
  const rawName = actor.name.trim();
  if (!rawName) return t('task.actor.ai');
  return `${t('task.actor.ai')} (${rawName})`;
}

export function reportTaskDetailActionError(action: string, error: unknown, taskId?: string): void {
  const details = toIpcErrorMessage(error);
  const idContext = taskId ? ` taskId=${taskId}` : '';
  reportClientError(
    'ui.task_detail.action_error',
    `TaskDetail action failed: ${action}`,
    error,
    `${details}${idContext}`,
    'warn',
  );
}

export function normalizeDeferDate(value: string): string {
  const raw = value.trim();
  if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) return raw;
  const parsed = new Date(raw);
  if (!Number.isNaN(parsed.getTime())) {
    return `${parsed.getFullYear()}-${String(parsed.getMonth() + 1).padStart(2, '0')}-${String(parsed.getDate()).padStart(2, '0')}`;
  }
  return raw;
}
