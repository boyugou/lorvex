import type { Priority } from '@lorvex/shared/types';

import type { QuickCaptureInitialData } from '@/app-shell/main-window/types';
import { parseEstimatedMinutesInput } from '@/lib/estimatedMinutes';
import type { ListWithCount } from '@/lib/ipc/tasks/models';
import type { SetupStatus } from '@/lib/ipc/settings';
import { tryParseJson } from '@/lib/security/jsonParse';
import { hasOnlyKeys, isPlainRecord as isRecord } from '@/lib/objectGuards';
import type { QuickDateOption } from './types';
import { serializeQuickCaptureSubmissionTags } from './tagDraft';

export interface QuickCaptureDraft {
  title: string;
  body: string;
  tagsInput: string;
  selectedListId: string | null;
}

interface QuickCaptureInitialState {
  title: string;
  body: string;
  showBody: boolean;
  selectedListId: string | null;
  dateOption: QuickDateOption;
  customDate: string;
  priority: Priority | null;
  tagsInput: string;
}

const QUICK_CAPTURE_DRAFT_KEYS = new Set([
  'body',
  'selectedListId',
  'tagsInput',
  'title',
]);

function hasOnlyQuickCaptureDraftKeys(value: Record<string, unknown>): boolean {
  return hasOnlyKeys(value, QUICK_CAPTURE_DRAFT_KEYS);
}

interface ResolveQuickCaptureInitialStateArgs {
  lists: ListWithCount[];
  initialData: QuickCaptureInitialData | undefined;
  initialDraft: QuickCaptureDraft | null;
  storedLastListId: string | null;
}

interface PrepareQuickCaptureSubmissionArgs {
  title: string;
  body: string;
  tagsInput: string;
  selectedListId: string | null;
  resolvedDueDate: string | undefined;
  priority: Priority | null;
  estimatedMinutesInput: string;
  activeNlDateCleanTitle?: string | null;
}

interface PreparedQuickCaptureSubmission {
  submitTitle: string;
  input: {
    listId?: string;
    dueDate?: string;
    priority: Priority | null;
    estimatedMinutes: number | null;
    body?: string;
    tags: string[] | null;
  };
}

interface QuickCaptureSetupBootstrap {
  selectedListIdToApply: string | null;
  resolvedListReady: boolean;
}

export function quickCaptureSetupListSignature(
  lists: readonly Pick<ListWithCount, 'id'>[],
): string {
  return lists.map((list) => list.id).sort().join('\n');
}

export function shouldLoadQuickCaptureSetupStatus({
  selectedListId,
  currentListSignature,
  loadedListSignature,
}: {
  selectedListId: string | null;
  currentListSignature: string;
  loadedListSignature: string | null;
}): boolean {
  return !selectedListId && currentListSignature !== loadedListSignature;
}

export function readQuickCaptureDraftFromStorageValue(raw: string | null): QuickCaptureDraft | null {
  if (!raw) return null;
  const parsed = tryParseJson(raw);
  if (!parsed.ok || !isRecord(parsed.value) || !hasOnlyQuickCaptureDraftKeys(parsed.value)) {
    return null;
  }
  const draft = parsed.value;
  if (
    typeof draft.title !== 'string'
    || typeof draft.body !== 'string'
    || typeof draft.tagsInput !== 'string'
    || (
      draft.selectedListId !== null
      && typeof draft.selectedListId !== 'string'
    )
  ) {
    return null;
  }
  return {
    title: draft.title,
    body: draft.body,
    tagsInput: draft.tagsInput,
    selectedListId: draft.selectedListId,
  };
}

export function restoreLastListIdFromValue(
  lists: ListWithCount[],
  storedListId: string | null,
): string | null {
  if (!storedListId) return null;
  return lists.some((list) => list.id === storedListId) ? storedListId : null;
}

export function resolveQuickCaptureSetupBootstrap({
  lists,
  selectedListId,
  setupStatus,
}: {
  lists: readonly Pick<ListWithCount, 'id'>[];
  selectedListId: string | null;
  setupStatus: Pick<SetupStatus, 'default_list_id' | 'default_list_ready' | 'normal_task_creation_ready'> | null;
}): QuickCaptureSetupBootstrap {
  if (selectedListId) {
    return {
      selectedListIdToApply: null,
      resolvedListReady: true,
    };
  }

  if (!setupStatus?.normal_task_creation_ready) {
    return {
      selectedListIdToApply: null,
      resolvedListReady: false,
    };
  }

  const defaultListId = setupStatus.default_list_ready ? setupStatus.default_list_id : null;
  const defaultListExistsLocally = Boolean(
    defaultListId && lists.some((list) => list.id === defaultListId),
  );

  return {
    selectedListIdToApply: defaultListExistsLocally ? defaultListId : null,
    resolvedListReady: true,
  };
}

function resolveInitialListId(
  lists: ListWithCount[],
  storedLastListId: string | null,
  initialData?: QuickCaptureInitialData,
): string | null {
  if (initialData?.list) {
    const target = initialData.list.toLowerCase();
    const match = lists.find(
      (list) => list.name.toLowerCase() === target || list.id === initialData.list,
    );
    if (match) return match.id;
  }
  return restoreLastListIdFromValue(lists, storedLastListId);
}

function resolveInitialPriority(initialData?: QuickCaptureInitialData): Priority | null {
  const priority = initialData?.priority;
  if (priority === 1 || priority === 2 || priority === 3) return priority;
  return null;
}

export function resolveQuickCaptureInitialState({
  lists,
  initialData,
  initialDraft,
  storedLastListId,
}: ResolveQuickCaptureInitialStateArgs): QuickCaptureInitialState {
  // initialData wins per-field where present, the persisted draft fills in
  // the rest. This is what makes the Retry affordance whole: the failed
  // submission's `failureRetryData` only round-trips title/list/due/priority,
  // so without the draft fallback the user lost body/tags/estimatedMinutes
  // every time they retried (UX bug U4).
  const initialListId = resolveInitialListId(lists, storedLastListId, initialData);
  const draftListIdValid =
    initialDraft?.selectedListId
    && lists.some((list) => list.id === initialDraft.selectedListId)
      ? initialDraft.selectedListId
      : null;
  // Precedence: `initialData.list` resolves to a real list ID via
  // `initialListId`; if it doesn't match, fall through to the draft,
  // then to the stored "last list" restore. Same precedence whether
  // the input came from `initialData` or only the draft.
  const selectedListId = initialData?.list
    ? (initialListId ?? draftListIdValid ?? null)
    : (draftListIdValid ?? initialListId);

  return {
    title: initialData?.title ?? initialDraft?.title ?? '',
    body: initialDraft?.body ?? '',
    showBody: Boolean(initialDraft?.body),
    selectedListId,
    dateOption: initialData?.due ? 'custom' : 'none',
    customDate: initialData?.due ?? '',
    priority: resolveInitialPriority(initialData),
    tagsInput: initialDraft?.tagsInput ?? '',
  };
}

export function prepareQuickCaptureSubmission({
  title,
  body,
  tagsInput,
  selectedListId,
  resolvedDueDate,
  priority,
  estimatedMinutesInput,
  activeNlDateCleanTitle,
}: PrepareQuickCaptureSubmissionArgs): PreparedQuickCaptureSubmission | null {
  const estimatedMinutes = parseEstimatedMinutesInput(estimatedMinutesInput);
  if (estimatedMinutesInput.trim() && estimatedMinutes == null) {
    return null;
  }

  const input: PreparedQuickCaptureSubmission['input'] = {
    priority,
    estimatedMinutes,
    tags: serializeQuickCaptureSubmissionTags(tagsInput),
  };
  if (selectedListId) {
    input.listId = selectedListId;
  }
  if (resolvedDueDate) {
    input.dueDate = resolvedDueDate;
  }
  const trimmedBody = body.trim();
  if (trimmedBody) {
    input.body = trimmedBody;
  }

  return {
    submitTitle: activeNlDateCleanTitle ?? title.trim(),
    input,
  };
}
