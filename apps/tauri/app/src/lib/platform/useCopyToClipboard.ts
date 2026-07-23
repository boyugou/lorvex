import { useCallback, useRef, useState } from 'react';
import { toast } from '../notifications/toast';
import { useI18n } from '../i18n';
import { useLazyRef } from '../useLazyRef';
import { createClipboardCopyController } from './useCopyToClipboard.logic';
import { createBrowserClipboardWriter } from './useCopyToClipboard.runtime';

/**
 * Shared hook for copy-to-clipboard with loading state and toast feedback.
 * Replaces the pattern of [copying, setCopying] + try/catch/toast
 * duplicated across 18+ components.
 */
export function useCopyToClipboard() {
  const [copying, setCopying] = useState(false);
  const { t } = useI18n();
  const translationsRef = useRef({
    success: t('common.copied'),
    error: t('common.error'),
  });
  translationsRef.current = {
    success: t('common.copied'),
    error: t('common.error'),
  };
  const clipboardWriterRef = useLazyRef(() => createBrowserClipboardWriter());
  const controllerRef = useLazyRef(() =>
    createClipboardCopyController(
      {
        writeText: clipboardWriterRef.current.writeText,
        notifyCopyingChange: (nextCopying) => setCopying(nextCopying),
        notifySuccess: (message) => toast.success(message),
        notifyError: (error, fallbackMessage) => toast.errorWithDetail(error, fallbackMessage),
      },
      () => translationsRef.current.success,
      () => translationsRef.current.error,
    ),
  );

  const copy = useCallback(async (text: string, successMessage?: string) => {
    await controllerRef.current.copy(text, successMessage);
    // controllerRef is a stable MutableRefObject from useLazyRef.
  }, [controllerRef]);

  return { copy, copying };
}
