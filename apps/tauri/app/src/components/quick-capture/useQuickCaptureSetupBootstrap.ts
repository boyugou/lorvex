import { useEffect, useMemo, useRef, useState, type Dispatch, type SetStateAction } from 'react';

import { reportClientError } from '@/lib/errors/errorLogging';
import type { ListWithCount } from '@/lib/ipc/tasks/models';
import { getSetupStatus, type SetupStatus } from '@/lib/ipc/settings';

import {
  quickCaptureSetupListSignature,
  resolveQuickCaptureSetupBootstrap,
  shouldLoadQuickCaptureSetupStatus,
} from './useQuickCaptureForm.logic';

interface UseQuickCaptureSetupBootstrapArgs {
  lists: ListWithCount[];
  selectedListId: string | null;
  setSelectedListId: Dispatch<SetStateAction<string | null>>;
}

export function useQuickCaptureSetupBootstrap({
  lists,
  selectedListId,
  setSelectedListId,
}: UseQuickCaptureSetupBootstrapArgs): ReturnType<typeof resolveQuickCaptureSetupBootstrap> {
  const [setupStatus, setSetupStatus] = useState<SetupStatus | null>(null);
  const setupStatusLoadSeqRef = useRef(0);
  const setupStatusLoadedListSignatureRef = useRef<string | null>(null);

  const setupStatusListSignature = useMemo(
    () => quickCaptureSetupListSignature(lists),
    [lists],
  );

  useEffect(() => {
    if (!shouldLoadQuickCaptureSetupStatus({
      selectedListId,
      currentListSignature: setupStatusListSignature,
      loadedListSignature: setupStatusLoadedListSignatureRef.current,
    })) {
      return;
    }
    let cancelled = false;
    const loadSeq = setupStatusLoadSeqRef.current + 1;
    setupStatusLoadSeqRef.current = loadSeq;
    setupStatusLoadedListSignatureRef.current = setupStatusListSignature;
    void getSetupStatus()
      .then((status) => {
        if (!cancelled && setupStatusLoadSeqRef.current === loadSeq) {
          setSetupStatus(status);
        }
      })
      .catch((error) => { reportClientError('quick-capture.setup', 'Failed to load setup status', error); });
    return () => {
      cancelled = true;
    };
  }, [selectedListId, setupStatusListSignature]);

  const setupBootstrap = useMemo(() => resolveQuickCaptureSetupBootstrap({
    lists,
    selectedListId,
    setupStatus,
  }), [lists, selectedListId, setupStatus]);

  useEffect(() => {
    if (setupBootstrap.selectedListIdToApply) {
      setSelectedListId(setupBootstrap.selectedListIdToApply);
    }
  }, [setSelectedListId, setupBootstrap.selectedListIdToApply]);

  return setupBootstrap;
}
