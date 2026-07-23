import { useCallback, useEffect, useRef, useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { listen } from '@/lib/platform/events';
import { getAiMemory, type AIMemoryEntry } from '@/lib/ipc/memory';
import { authenticateBiometrics } from '@/lib/ipc/runtime';
import { useI18n } from '@/lib/i18n';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { formatTimestamp } from '@/lib/dates/dateLocale';
import { reportClientError } from '@/lib/errors/errorLogging';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { usePreference } from '@/lib/query/usePreference';
import { PREF_MEMORY_LOCK_ENABLED } from '@/lib/preferences/keys';
import { createAsyncTauriListenerScope } from '@/lib/tauriListenerLifecycle';
import { useCopyToClipboard } from '@/lib/platform/useCopyToClipboard';
import { useMounted } from '@/lib/useMounted';
import {
  DEFAULT_MEMORY_LOCK_STATE,
  parseMemoryLockPreference,
  reconcileMemoryLockEnabledState,
} from '@/lib/memoryLockPreference';
import { useRuntimeProfile } from '@/lib/useRuntimeProfile';
import { useMcpServerStatus } from '@/lib/hooks/useMcpServerStatus';
import {
  readStoredDraft,
  writeStoredDraft,
  type AddMemoryDraft,
} from './addDraftStorage';
import { CLUSTER_KEY_PLACEHOLDER } from './clusterLabels';
import type { MemoryCluster } from './helpers';

// Reserved key for the single human-owned notes block — kept in
// lock-step with `lorvex_domain::memory::MEMORY_KEY_NOTES_FOR_AI`.
const NOTES_FOR_AI_KEY = 'notes_for_ai';

/**
 * Data + interaction model behind `AIMemoryView`. Owns:
 * - the search/draft/add-form UI state
 * - the biometric memory-lock state machine (enabled, locked,
 *   auth error, blur listener, query-cache scrubbing on lock)
 * - the persisted "+ Add memory" draft (read on mount, restored on
 *   every lock→unlock transition, written only via the
 *   `hasUserInput`-gated `persistDraft` path so CTA seeds leave no
 *   localStorage residue)
 * - the memory query + invalidation handle + copy-all action
 *
 * Returns a flat record consumed directly by the view component so
 * the view stays a pure render of the controller's state.
 */
export function useAIMemoryViewController() {
  const { t, locale } = useI18n();
  const mcpStatus = useMcpServerStatus();
  // Only swap the copy when the query actually resolved to
  // `resolved: false`. While it's still loading (or on a runtime
  // that doesn't host MCP, like mobile builds), keep the normal empty state so
  // we don't mis-advise a user who already has an assistant
  // connected.
  const mcpUnconfigured = mcpStatus !== null && mcpStatus.resolved === false;
  const { timezone } = useConfiguredDayContext();
  const qc = useQueryClient();
  const [search, setSearch] = useState('');
  const [addFormOpen, setAddFormOpen] = useState(false);
  // Lazily read any stashed draft on first render so we re-open the
  // form pre-filled when the user returns after a memory-lock blur.
  const [addFormDraft, setAddFormDraft] = useState<AddMemoryDraft | null>(() => readStoredDraft());
  // Persist real user input only. Wired into `AddMemoryForm` as
  // `onDraftChange`, which gates emission behind its `hasUserInput`
  // flag — so reaching this callback implies the user has actually
  // typed something. Mirrors the value into local state too so a
  // subsequent re-open (e.g. lock blur) sees the same draft.
  //
  // The CTA seed path (`openAddFormForCluster`) deliberately does
  // NOT route through here — it calls `setAddFormDraft` directly and
  // skips the localStorage write, so an abandoned CTA leaves zero
  // residue.
  const persistDraft = useCallback((draft: AddMemoryDraft | null) => {
    setAddFormDraft(draft);
    writeStoredDraft(draft);
  }, []);
  const { supportsBiometricLock } = useRuntimeProfile();

  const [memoryLockState, setMemoryLockState] = useState(
    supportsBiometricLock ? DEFAULT_MEMORY_LOCK_STATE : { lockEnabled: false, isLocked: false },
  );
  const [authError, setAuthError] = useState<string | null>(null);
  const lastMemoryLockErrorRef = useRef<string | null>(null);
  const memoryViewMountedRef = useMounted();
  const { lockEnabled, isLocked } = memoryLockState;

  // Rehydrate the add-form draft on every lock→unlock transition
  // (not just first mount). A user who locks, returns, unlocks,
  // types, blurs (locks again), then re-unlocks must land back on
  // the same pre-filled form. Reading state directly from
  // localStorage at the moment of unlock is the cheapest correct
  // trigger — the writer (`persistDraft`) keeps the stored value
  // current.
  const previouslyLockedRef = useRef(isLocked);
  useEffect(() => {
    const wasLocked = previouslyLockedRef.current;
    previouslyLockedRef.current = isLocked;
    if (wasLocked && !isLocked) {
      const stashed = readStoredDraft();
      if (stashed) {
        setAddFormDraft(stashed);
        setAddFormOpen(true);
      }
    }
  }, [isLocked]);

  // Initial-mount rehydrate — covers the case where a draft was
  // stashed by a prior session and the user comes back without ever
  // toggling the lock during this session.
  useEffect(() => {
    if (addFormDraft && !addFormOpen) {
      setAddFormOpen(true);
    }
    // Intentionally only run when the rehydrated value first
    // arrives.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const {
    value: memoryLockPreferenceEnabled,
    error: memoryLockPreferenceError,
    isLoading: isMemoryLockPreferenceLoading,
  } = usePreference(
    PREF_MEMORY_LOCK_ENABLED,
    parseMemoryLockPreference,
    { staleTime: 0 },
  );

  useEffect(() => {
    if (isMemoryLockPreferenceLoading) return;
    if (!supportsBiometricLock) {
      setMemoryLockState({ lockEnabled: false, isLocked: false });
      return;
    }
    setMemoryLockState(current => reconcileMemoryLockEnabledState(current, memoryLockPreferenceEnabled));
  }, [isMemoryLockPreferenceLoading, memoryLockPreferenceEnabled, supportsBiometricLock]);

  useEffect(() => {
    if (!memoryLockPreferenceError) {
      lastMemoryLockErrorRef.current = null;
      return;
    }

    const nextError = memoryLockPreferenceError instanceof Error
      ? memoryLockPreferenceError.message
      : String(memoryLockPreferenceError);
    if (lastMemoryLockErrorRef.current === nextError) return;

    lastMemoryLockErrorRef.current = nextError;
    setMemoryLockState(DEFAULT_MEMORY_LOCK_STATE);
    reportClientError(
      'memory.lockPreference',
      'Failed to load AI memory lock preference',
      memoryLockPreferenceError,
    );
  }, [memoryLockPreferenceError]);

  useEffect(() => {
    if (!lockEnabled) return;
    let cancelled = false;
    const listeners = createAsyncTauriListenerScope();
    // two-layer guard against the unmount race.
    //   (1) The blur callback itself bails when `cancelled` flipped
    //       between Tauri delivering the event and React running the
    //       handler — `listen()` keeps a strong ref to the callback,
    //       so unbinding via `unlisten()` can race with an in-flight
    //       blur dispatch.
    //   (2) The `.then(fn)` arm re-checks `cancelled` so an unmount
    //       that happens after the promise resolved but before the
    //       microtask drained still releases the listener immediately
    //       (the prior code did this — kept and documented).
    listeners.add(
      listen('tauri://blur', () => {
        if (cancelled) return;
        setMemoryLockState(current => (current.lockEnabled ? { ...current, isLocked: true } : current));
      }),
      (error) => {
        if (cancelled) return;
        reportClientError('memory.blurListener', 'Failed to subscribe to AI memory blur listener', error);
      },
    );
    return () => {
      cancelled = true;
      listeners.dispose();
    };
  }, [lockEnabled]);

  useEffect(() => {
    if (!lockEnabled || !isLocked) return;
    qc.removeQueries({ queryKey: QUERY_KEYS.aiMemory() });
    qc.removeQueries({ queryKey: QUERY_KEYS.memoryHistory() });
  }, [lockEnabled, isLocked, qc]);

  const handleUnlock = useCallback(async () => {
    setAuthError(null);
    try {
      const ok = await authenticateBiometrics(t('memory.authReason'));
      if (!memoryViewMountedRef.current) return;
      if (ok) {
        setMemoryLockState(current => ({ ...current, isLocked: false }));
      } else {
        setAuthError(t('memory.biometricAuthFailed'));
      }
    } catch (e) {
      reportClientError('memory.biometricAuth', 'Biometric authentication failed', e);
      if (!memoryViewMountedRef.current) return;
      setAuthError(t('memory.biometricAuthFailed'));
    }
  }, [memoryViewMountedRef, t]);

  const {
    data: entries = [],
    isLoading,
    isError,
    refetch,
  } = useQuery({
    queryKey: QUERY_KEYS.aiMemory(),
    queryFn: ({ signal }) => getAiMemory(signal),
    enabled: !lockEnabled || !isLocked,
  });

  // The reserved `notes_for_ai` key always renders in its own
  // section. Everything else — whether the assistant wrote it or the
  // user seeded it via the "+ Add memory" form — shows in the
  // structured-memory list below. Row ownership is derived from the
  // latest revision's actor, so user-seeded rows render with a human
  // attribution badge alongside assistant-authored ones.
  const notesForAi = entries.find(e => e.key === NOTES_FOR_AI_KEY) ?? null;
  const listEntries = entries.filter(e => e.key !== NOTES_FOR_AI_KEY);

  const normalizedSearch = search.toLowerCase();
  const filteredListEntries = listEntries.filter((entry: AIMemoryEntry) => {
    if (!normalizedSearch) return true;
    return (
      entry.key.toLowerCase().includes(normalizedSearch) ||
      entry.content.toLowerCase().includes(normalizedSearch)
    );
  });

  const { copy, copying } = useCopyToClipboard();
  const handleCopyAll = useCallback(async () => {
    if (copying || entries.length === 0) return;
    const lines: string[] = [
      `${t('memory.title')} — ${formatTimestamp(new Date().toISOString(), locale, timezone, { dateStyle: 'short' })}\n`,
    ];
    for (const entry of entries) {
      lines.push(`[${entry.key}]`);
      lines.push(entry.content);
      lines.push('');
    }
    await copy(lines.join('\n').trimEnd(), t('memory.copied'));
  }, [copy, copying, entries, locale, t, timezone]);

  const invalidateMemory = useCallback(() => {
    void qc.invalidateQueries({ queryKey: QUERY_KEYS.aiMemory() });
    void qc.invalidateQueries({ queryKey: QUERY_KEYS.memoryHistory() });
  }, [qc]);

  // CTA seed path: clicking an empty-cluster row pre-fills the
  // form's key with `<cluster>.` so the new entry lands in that
  // lane. In-memory only — no localStorage write — so abandoning
  // the form without typing leaves zero residue. Persistence
  // happens via `persistDraft`, which the form invokes from its
  // `hasUserInput`-gated mirror effect once real user input
  // actually arrives.
  const openAddFormForCluster = useCallback((cluster?: MemoryCluster) => {
    if (cluster) {
      setAddFormDraft({ key: CLUSTER_KEY_PLACEHOLDER[cluster], content: '' });
    }
    setAddFormOpen(true);
  }, []);

  const openAddForm = useCallback(() => setAddFormOpen(true), []);
  const closeAddForm = useCallback(() => setAddFormOpen(false), []);

  return {
    // i18n + day context
    t,
    locale,
    timezone,
    // mcp configuration hint
    mcpUnconfigured,
    // search
    search,
    setSearch,
    normalizedSearch,
    // add form
    addFormOpen,
    openAddForm,
    closeAddForm,
    openAddFormForCluster,
    addFormDraft,
    persistDraft,
    // memory lock
    lockEnabled,
    isLocked,
    authError,
    handleUnlock,
    // data
    entries,
    notesForAi,
    listEntries,
    filteredListEntries,
    isLoading,
    isError,
    refetch,
    invalidateMemory,
    // copy
    copying,
    handleCopyAll,
  };
}
