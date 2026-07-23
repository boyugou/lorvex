import { useEffect, useRef, useState } from 'react';

import { useConfiguredDayContext } from '@/lib/dayContext';
import type { ListWithCount } from '@/lib/ipc/tasks/models';
import { useI18n } from '@/lib/i18n';
import type { QuickCaptureInitialData } from '@/app-shell/main-window/types';
import type { Priority } from '@lorvex/shared/types';

import { buildQuickCaptureFormViewModel } from './quickCaptureFormViewModel';
import {
  readQuickCaptureDraft,
  restoreQuickCaptureLastListId,
  useQuickCaptureDraftAutosave,
} from './useQuickCaptureDraft';
import { resolveQuickCaptureInitialState } from './useQuickCaptureForm.logic';
import { useQuickCaptureDateResolution } from './useQuickCaptureDateResolution';
import { useQuickCaptureSetupBootstrap } from './useQuickCaptureSetupBootstrap';
import { useQuickCaptureSubmit } from './useQuickCaptureSubmit';

interface UseQuickCaptureFormOptions {
  lists: ListWithCount[];
  onClose: () => void;
  initialData?: QuickCaptureInitialData | undefined;
  sessionId?: number | null | undefined;
  /**
   * invoked when a fire-and-forget submit fails after
   * the modal has already been closed. The host wires this to the
   * MainWindow controller's `openQuickCapture` so the user can re-open
   * the form pre-populated from the just-restored draft and retry.
   */
  onReopenForRetry?: ((draft: QuickCaptureInitialData) => void) | undefined;
}

export function useQuickCaptureForm({
  lists,
  onClose,
  initialData,
  onReopenForRetry,
  sessionId,
}: UseQuickCaptureFormOptions) {
  const initialStateRef = useRef(
    resolveQuickCaptureInitialState({
      lists,
      initialData,
      initialDraft: readQuickCaptureDraft(),
      storedLastListId: restoreQuickCaptureLastListId(lists),
    }),
  );
  const appliedSessionIdRef = useRef<number | null | undefined>(sessionId);
  const initialState = initialStateRef.current;
  const [title, setTitle] = useState(initialState.title);
  const [body, setBody] = useState(initialState.body);
  const [showBody, setShowBody] = useState(initialState.showBody);
  const [selectedListId, setSelectedListId] = useState<string | null>(initialState.selectedListId);
  const [priority, setPriority] = useState<Priority | null>(initialState.priority);
  const [estimatedMinutes, setEstimatedMinutes] = useState('');
  const [tagsInput, setTagsInput] = useState(initialState.tagsInput);
  const [isComposing, setIsComposing] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);
  const { t, locale } = useI18n();
  const dayContext = useConfiguredDayContext();

  const date = useQuickCaptureDateResolution({
    title,
    locale,
    t,
    dayContext,
    initialDateOption: initialState.dateOption,
    initialCustomDate: initialState.customDate,
  });
  const { resetDateState } = date;

  useEffect(() => {
    if (sessionId == null || appliedSessionIdRef.current === sessionId) return;
    const nextState = resolveQuickCaptureInitialState({
      lists,
      initialData,
      initialDraft: readQuickCaptureDraft(),
      storedLastListId: restoreQuickCaptureLastListId(lists),
    });
    appliedSessionIdRef.current = sessionId;
    initialStateRef.current = nextState;
    setTitle(nextState.title);
    setBody(nextState.body);
    setShowBody(nextState.showBody);
    setSelectedListId(nextState.selectedListId);
    resetDateState({
      dateOption: nextState.dateOption,
      customDate: nextState.customDate,
    });
    setPriority(nextState.priority);
    setEstimatedMinutes('');
    setTagsInput(nextState.tagsInput);
    setIsComposing(false);
  }, [initialData, lists, resetDateState, sessionId]);

  // Modal's `focusTarget` prop (wired to `form.inputRef` in
  // `QuickCapture.tsx`) is the canonical focus-on-mount path. A duplicate
  // local effect here would race the modal's focus pass on reopen and
  // occasionally steal focus from the user mid-type when the parent
  // state ticked between mount and the effect flush.
  useQuickCaptureDraftAutosave({
    title,
    body,
    tagsInput,
    selectedListId,
  });

  const setupBootstrap = useQuickCaptureSetupBootstrap({
    lists,
    selectedListId,
    setSelectedListId,
  });

  function togglePriority(value: Priority): void {
    setPriority(priority === value ? null : value);
  }

  function clearPriority(): void {
    setPriority(null);
  }

  function toggleDuration(minutes: number): void {
    setEstimatedMinutes(estimatedMinutes === String(minutes) ? '' : String(minutes));
  }

  function clearDuration(): void {
    setEstimatedMinutes('');
  }

  const submit = useQuickCaptureSubmit({
    title,
    body,
    tagsInput,
    selectedListId,
    priority,
    estimatedMinutes,
    activeNlDate: date.activeNlDate,
    resolvedDueDate: date.resolvedDueDate,
    setTitle,
    setBody,
    setShowBody,
    resetDateState: date.resetDateState,
    setPriority,
    setEstimatedMinutes,
    setTagsInput,
    inputRef,
    onClose,
    onReopenForRetry,
    sessionId,
  });

  const listRequiredHint = !setupBootstrap.resolvedListReady
    ? t('capture.listRequiredHint')
    : null;

  return buildQuickCaptureFormViewModel({
    // Title + body
    title,
    setTitle,
    body,
    setBody,
    showBody,
    setShowBody,

    // IME composition
    isComposing,
    setIsComposing,

    // Date
    dateOption: date.dateOption,
    customDate: date.customDate,
    setCustomDate: date.setCustomDate,
    setDateOption: date.setDateOption,
    toggleDateOption: date.toggleDateOption,
    clearDate: date.clearDate,
    activeDateLabel: date.dateLabel(),

    // Natural-language detected date
    activeNlDate: date.activeNlDate,
    clearNlDate: date.clearNlDate,

    // Priority
    priority,
    togglePriority,
    clearPriority,

    // Duration
    estimatedMinutes,
    setEstimatedMinutes,
    toggleDuration,
    clearDuration,

    // Tags
    tagsInput,
    setTagsInput,

    // List
    selectedListId,
    setSelectedListId,
    listRequiredHint,

    // Submission
    submitting: submit.submitting,
    canSubmit: submit.canSubmitBase && setupBootstrap.resolvedListReady,
    handleSubmit: submit.handleSubmit,
    handleSubmitAndContinue: submit.handleSubmitAndContinue,
    requestClose: submit.requestClose,

    // Refs
    inputRef,

    // i18n
    t,
  });
}
