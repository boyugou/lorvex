import { useCallback, useEffect, useState, type RefObject } from 'react';
import { useQueryClient } from '@tanstack/react-query';

import { confirm } from '@/lib/dialogs/confirm';
import { reportClientError } from '@/lib/errors/errorLogging';
import { MAX_ESTIMATED_MINUTES } from '@/lib/estimatedMinutes';
import { getDeviceState, setDeviceState } from '@/lib/ipc/settings';
import { quickCapture } from '@/lib/ipc/tasks/mutations/quickCapture';
import { useI18n } from '@/lib/i18n';
import { DEV_FIRST_TASK_CELEBRATED } from '@/lib/preferences/keys';
import { invalidateListContextTaskWriteQueries } from '@/lib/query/queryKeys';
import { formatShortcut } from '@/lib/shortcuts';
import { writeDraft } from '@/lib/storage/drafts';
import { toast } from '@/lib/notifications/toast';
import { useMounted } from '@/lib/useMounted';
import type { QuickCaptureInitialData } from '@/app-shell/main-window/types';
import type { ParseResult } from '@/lib/dateParser';
import type { Priority } from '@lorvex/shared/types';

import { hasQuickCaptureDraftContent, QUICK_CAPTURE_DRAFT_STORAGE_KEY } from './quickCaptureDraftAutosave.runtime';
import type { QuickDateOption } from './types';
import { clearQuickCaptureDraft, persistQuickCaptureListId } from './useQuickCaptureDraft';
import { type QuickCaptureDraft, prepareQuickCaptureSubmission } from './useQuickCaptureForm.logic';

interface UseQuickCaptureSubmitArgs {
  title: string;
  body: string;
  tagsInput: string;
  selectedListId: string | null;
  priority: Priority | null;
  estimatedMinutes: string;
  activeNlDate: ParseResult | null;
  resolvedDueDate: () => string | undefined;
  setTitle: (value: string) => void;
  setBody: (value: string) => void;
  setShowBody: (value: boolean) => void;
  resetDateState: (nextState: { dateOption: QuickDateOption; customDate: string }) => void;
  setPriority: (value: Priority | null) => void;
  setEstimatedMinutes: (value: string) => void;
  setTagsInput: (value: string) => void;
  inputRef: RefObject<HTMLInputElement | null>;
  onClose: () => void;
  onReopenForRetry?: ((draft: QuickCaptureInitialData) => void) | undefined;
  sessionId?: number | null | undefined;
}

export function useQuickCaptureSubmit({
  title,
  body,
  tagsInput,
  selectedListId,
  priority,
  estimatedMinutes,
  activeNlDate,
  resolvedDueDate,
  setTitle,
  setBody,
  setShowBody,
  resetDateState,
  setPriority,
  setEstimatedMinutes,
  setTagsInput,
  inputRef,
  onClose,
  onReopenForRetry,
  sessionId,
}: UseQuickCaptureSubmitArgs) {
  const [submitting, setSubmitting] = useState(false);
  const mountedRef = useMounted();
  const qc = useQueryClient();
  const { t, format, formatNumber } = useI18n();

  useEffect(() => {
    setSubmitting(false);
  }, [sessionId]);

  const getPreparedSubmission = useCallback(() => {
    return prepareQuickCaptureSubmission({
      title,
      body,
      tagsInput,
      selectedListId,
      resolvedDueDate: resolvedDueDate(),
      priority,
      estimatedMinutesInput: estimatedMinutes,
      activeNlDateCleanTitle: activeNlDate?.cleanTitle ?? null,
    });
  }, [activeNlDate, body, estimatedMinutes, priority, resolvedDueDate, selectedListId, tagsInput, title]);

  const doSubmit = useCallback(async (): Promise<boolean> => {
    if (!title.trim() || submitting) return false;
    setSubmitting(true);
    const failureDraft: QuickCaptureDraft = {
      title,
      body,
      tagsInput,
      selectedListId,
    };
    const dueDate = resolvedDueDate();
    const failureRetryData: QuickCaptureInitialData = {
      title,
      ...(selectedListId ? { list: selectedListId } : {}),
      ...(dueDate ? { due: dueDate } : {}),
      ...(priority != null ? { priority } : {}),
    };
    try {
      const prepared = getPreparedSubmission();
      if (!prepared) {
        toast.error(
          format('capture.durationInvalid', { max: formatNumber(MAX_ESTIMATED_MINUTES) }),
        );
        if (mountedRef.current) {
          setSubmitting(false);
        }
        return false;
      }
      const captured = await quickCapture({
        title: prepared.submitTitle,
        ...prepared.input,
      });
      persistQuickCaptureListId(selectedListId);
      invalidateListContextTaskWriteQueries(qc, { listId: selectedListId });
      clearQuickCaptureDraft();
      void celebrateFirstCaptureIfEligible(captured.title, format);
      toast.success(format('capture.taskCreateSuccessWithTitle', { title: captured.title }));
      if (mountedRef.current) {
        setSubmitting(false);
      }
      return true;
    } catch (err) {
      reportClientError(
        'quickCapture.submit',
        'Quick capture failed',
        err,
        selectedListId ?? 'no-list',
      );
      if (hasQuickCaptureDraftContent(failureDraft)) {
        writeDraft(QUICK_CAPTURE_DRAFT_STORAGE_KEY, JSON.stringify(failureDraft));
      }
      if (onReopenForRetry) {
        toast.error(
          t('common.error'),
          {
            label: t('common.retry'),
            onClick: () => onReopenForRetry(failureRetryData),
          },
          { context: 'quickCapture.submitFailed' },
        );
      } else {
        toast.errorWithDetail(err, t('common.error'));
      }
      if (mountedRef.current) {
        setSubmitting(false);
      }
      return false;
    }
  }, [
    body,
    format,
    formatNumber,
    getPreparedSubmission,
    mountedRef,
    onReopenForRetry,
    priority,
    qc,
    resolvedDueDate,
    selectedListId,
    submitting,
    t,
    tagsInput,
    title,
  ]);

  const handleSubmit = useCallback(async (): Promise<void> => {
    if (!title.trim() || submitting) return;
    if (!getPreparedSubmission()) {
      toast.error(
        format('capture.durationInvalid', { max: formatNumber(MAX_ESTIMATED_MINUTES) }),
      );
      return;
    }
    onClose();
    void doSubmit();
  }, [doSubmit, format, formatNumber, getPreparedSubmission, onClose, submitting, title]);

  const handleSubmitAndContinue = useCallback(async (): Promise<void> => {
    const ok = await doSubmit();
    if (!ok) return;
    setTitle('');
    setBody('');
    setShowBody(false);
    resetDateState({ dateOption: 'none', customDate: '' });
    setPriority(null);
    setEstimatedMinutes('');
    setTagsInput('');
    inputRef.current?.focus();
  }, [
    doSubmit,
    inputRef,
    resetDateState,
    setBody,
    setEstimatedMinutes,
    setPriority,
    setShowBody,
    setTagsInput,
    setTitle,
  ]);

  const isDirty =
    title.trim().length > 0 ||
    body.trim().length > 0 ||
    tagsInput.trim().length > 0 ||
    resolvedDueDate() != null ||
    priority != null ||
    estimatedMinutes.length > 0;

  const requestClose = useCallback(async () => {
    if (submitting) {
      onClose();
      return;
    }
    if (!isDirty) {
      onClose();
      return;
    }
    const ok = await confirm({
      title: t('quickCapture.discardConfirmTitle'),
      message: t('quickCapture.discardConfirmMessage'),
      variant: 'danger',
      confirmLabel: t('quickCapture.discardConfirmAction'),
      cancelLabel: t('quickCapture.discardConfirmKeepEditing'),
    });
    if (ok) {
      clearQuickCaptureDraft();
      onClose();
    }
  }, [isDirty, onClose, submitting, t]);

  return {
    canSubmitBase: title.trim().length > 0 && !submitting,
    handleSubmit,
    handleSubmitAndContinue,
    requestClose,
    submitting,
  };
}

async function celebrateFirstCaptureIfEligible(
  capturedTitle: string,
  format: ReturnType<typeof useI18n>['format'],
): Promise<void> {
  try {
    const previous = await getDeviceState(DEV_FIRST_TASK_CELEBRATED);
    if (previous) return;
    const now = new Date().toISOString();
    await setDeviceState(DEV_FIRST_TASK_CELEBRATED, now);
    const paletteShortcut = formatShortcut(['Mod', 'K']);
    const celebration = format('capture.firstTaskCelebration', {
      title: capturedTitle,
      paletteShortcut,
    });
    toast.info(celebration);
  } catch (error) {
    reportClientError(
      'quickCapture.firstTaskCelebration',
      'Failed to read/write first-task celebration latch',
      error,
      undefined,
      'warn',
    );
  }
}
