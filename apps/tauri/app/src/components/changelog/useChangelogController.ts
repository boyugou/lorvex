import { startTransition, useCallback, useEffect, useMemo, useState } from 'react';
import { useMounted } from '@/lib/useMounted';
import { useLazyRef } from '@/lib/useLazyRef';
import { useSuspenseQuery, useQueryClient } from '@tanstack/react-query';
import { clearChangelog } from '@/lib/ipc/settings';
import type { ChangelogEntry } from '@/lib/ipc/tasks/models';
import { getChangelog, undoChangelogEntry } from '@/lib/ipc/tasks/reviews';
import { confirm } from '@/lib/dialogs/confirm';
import { useI18n } from '@/lib/i18n';
import { QUERY_KEYS, invalidateChangelogQueries, invalidateTaskMutationQueries } from '@/lib/query/queryKeys';
import { useScrollRestore } from '@/lib/useScrollRestore';
import { useCopyToClipboard } from '@/lib/platform/useCopyToClipboard';
import {
  cleanupChangelogActionFeedbackReset,
  createBrowserChangelogActionFeedbackTimerHost,
  createChangelogActionFeedbackRuntimeState,
  scheduleChangelogActionFeedbackReset,
} from './actionFeedback.runtime';
import { formatChangelogActionErrorMessage } from './changelogError';

/** Operations that appear as filter chips. */
const FILTER_OPS = ['create', 'update', 'complete', 'delete', 'triage', 'plan'] as const;

const OP_ICONS: Record<string, string> = {
  create: '+',
  update: '~',
  complete: '\u2713',
  delete: '\u2717',
  triage: '\u2192',
  plan: '\u25C6',
};

interface ChangelogControllerState {
  // i18n
  t: ReturnType<typeof useI18n>['t'];
  format: ReturnType<typeof useI18n>['format'];
  locale: string;

  // scroll restore
  scroll: ReturnType<typeof useScrollRestore>;

  // filter / search state
  search: string;
  setSearch: React.Dispatch<React.SetStateAction<string>>;
  filterOp: string | null;
  setFilterOp: React.Dispatch<React.SetStateAction<string | null>>;
  filterEntity: string | null;
  setFilterEntity: React.Dispatch<React.SetStateAction<string | null>>;
  entryLimit: number;
  loadMore: () => void;

  // action feedback
  actionMessage: string | null;
  actionIsError: boolean;

  // clearing state
  clearing: boolean;
  copyingLog: boolean;

  // per-row undo state so the view can disable the
  // button while the mutation is in flight and avoid double-invocations
  // on rapid clicks. Keyed by ChangelogEntry.id.
  undoingEntryId: string | null;
  handleUndo: (entry: ChangelogEntry) => Promise<void>;

  // data
  entries: ChangelogEntry[];
  filteredEntries: ChangelogEntry[];
  opCounts: Record<string, number>;
  entityTypes: [string, number][];

  // callbacks
  copyChangelog: () => Promise<void>;
  handleClearAll: () => Promise<void>;
  refetchChangelog: () => void;

  // Freshness telemetry: ms-epoch the cache last received data
  // from the underlying query, and whether a refetch is currently in
  // flight. Lets the empty-state UI show "Last refreshed X ago" so
  // the user can distinguish "nothing logged yet" from "stale cache."
  dataUpdatedAt: number;
  isFetching: boolean;

  // constants re-exported for the view
  filterOps: readonly string[];
}

export function useChangelogController(): ChangelogControllerState {
  const { t, locale, format } = useI18n();
  const queryClient = useQueryClient();
  const scroll = useScrollRestore('ai-changelog');
  const [actionMessage, setActionMessage] = useState<string | null>(null);
  const [actionIsError, setActionIsError] = useState(false);
  const [search, setSearch] = useState('');
  const [filterOp, setFilterOp] = useState<string | null>(null);
  const [filterEntity, setFilterEntity] = useState<string | null>(null);
  const [entryLimit, setEntryLimit] = useState(50);
  const [clearing, setClearing] = useState(false);
  const [undoingEntryId, setUndoingEntryId] = useState<string | null>(null);
  const { copy: copyToClipboard, copying: copyingLog } = useCopyToClipboard();
  const changelogMountedRef = useMounted();

  const {
    data: entries,
    dataUpdatedAt,
    refetch: refetchChangelog,
    isFetching,
  } = useSuspenseQuery({
    queryKey: QUERY_KEYS.aiChangelog(entryLimit),
    queryFn: ({ signal }) => getChangelog(entryLimit, undefined, signal),
  });

  const filteredEntries = useMemo(() => {
    const q = search.trim().toLowerCase();
    return entries.filter(e => {
      if (filterOp && e.operation !== filterOp) return false;
      if (filterEntity && e.entity_type !== filterEntity) return false;
      if (q && !e.summary.toLowerCase().includes(q) && !(e.mcp_tool && e.mcp_tool.toLowerCase().includes(q))) return false;
      return true;
    });
  }, [entries, filterOp, filterEntity, search]);

  const opCounts = useMemo(() => {
    const counts: Record<string, number> = {};
    for (const e of entries) {
      counts[e.operation] = (counts[e.operation] ?? 0) + 1;
    }
    return counts;
  }, [entries]);

  const entityTypes = useMemo(() => {
    const counts: Record<string, number> = {};
    for (const e of entries) {
      counts[e.entity_type] = (counts[e.entity_type] ?? 0) + 1;
    }
    return Object.entries(counts).sort((a, b) => b[1] - a[1]);
  }, [entries]);

  const actionFeedbackRuntimeStateRef = useLazyRef(() => createChangelogActionFeedbackRuntimeState());
  const actionFeedbackTimerHostRef = useLazyRef(() => createBrowserChangelogActionFeedbackTimerHost());
  const setActionState = useCallback((message: string, isError: boolean) => {
    if (!changelogMountedRef.current) return;
    setActionMessage(message);
    setActionIsError(isError);
    scheduleChangelogActionFeedbackReset({
      delayMs: isError ? 8000 : 3000,
      isMounted: () => changelogMountedRef.current,
      setActionMessage,
      state: actionFeedbackRuntimeStateRef.current,
      timerHost: actionFeedbackTimerHostRef.current,
    });
    // The three *Ref values are stable MutableRefObjects from
    // useLazyRef / useMounted; their identities never change.
  }, [actionFeedbackRuntimeStateRef, actionFeedbackTimerHostRef, changelogMountedRef]);
  useEffect(() => () => {
    cleanupChangelogActionFeedbackReset(
      actionFeedbackRuntimeStateRef.current,
      actionFeedbackTimerHostRef.current,
    );
    // *Ref values are stable MutableRefObjects from useLazyRef.
  }, [actionFeedbackRuntimeStateRef, actionFeedbackTimerHostRef]);

  const copyChangelog = useCallback(async () => {
    if (copyingLog) return;
    const lines = filteredEntries.map(e => {
      const op = OP_ICONS[e.operation] ?? '\u00B7';
      const tool = e.mcp_tool ? ` (${e.mcp_tool})` : '';
      return `${op} ${e.summary}${tool}  \u2014  ${e.timestamp}`;
    });
    if (lines.length === 0) {
      setActionState(t('changelog.noEntriesToCopy'), false);
      return;
    }
    await copyToClipboard(lines.join('\n'), t('changelog.changelogCopied'));
  }, [copyingLog, copyToClipboard, filteredEntries, setActionState, t]);

  const handleClearAll = useCallback(async () => {
    if (clearing) return;
    const ok = await confirm({
      title: t('changelog.clearAll'),
      message: t('changelog.clearConfirm'),
      variant: 'danger',
      confirmLabel: t('changelog.clearAll'),
    });
    if (!ok) return;
    setClearing(true);
    try {
      const result = await clearChangelog();
      if (changelogMountedRef.current) {
        setActionState(format('changelog.cleared', { count: result.deleted }), false);
      }
      invalidateChangelogQueries(queryClient);
    } catch (error) {
      if (changelogMountedRef.current) {
        setActionState(formatChangelogActionErrorMessage(error, t('changelog.clearFailed')), true);
      }
    } finally {
      if (changelogMountedRef.current) {
        setClearing(false);
      }
    }
  }, [changelogMountedRef, clearing, format, queryClient, setActionState, t]);

  const loadMore = useCallback(() => {
    startTransition(() => setEntryLimit(prev => prev + 50));
  }, []);

  // per-row undo handler. Only rows with a non-null
  // `undo_token` are expected to trigger this; the view guards the
  // button on that. We still defend against a stale/expired token by
  // surfacing the backend error via `setActionState` rather than
  // throwing into the render tree.
  const handleUndo = useCallback(
    async (entry: ChangelogEntry): Promise<void> => {
      if (!entry.undo_token || undoingEntryId) return;
      setUndoingEntryId(entry.id);
      try {
        await undoChangelogEntry(entry.undo_token);
        if (!changelogMountedRef.current) return;
        setActionState(t('changelog.undoSuccess'), false);
        // Refresh the changelog itself (the undo appends a new "undo"
        // row) and any task-centric caches so the reopened task
        // re-appears in today / list / kanban surfaces.
        invalidateChangelogQueries(queryClient);
        if (entry.entity_id && entry.entity_type === 'task') {
          invalidateTaskMutationQueries(queryClient, {});
        }
      } catch (error) {
        if (!changelogMountedRef.current) return;
        setActionState(formatChangelogActionErrorMessage(error, t('changelog.undoFailed')), true);
      } finally {
        if (changelogMountedRef.current) {
          setUndoingEntryId(null);
        }
      }
    },
    [changelogMountedRef, queryClient, setActionState, t, undoingEntryId],
  );

  const triggerRefetch = useCallback(() => {
    void refetchChangelog();
  }, [refetchChangelog]);

  return {
    t,
    format,
    locale,
    scroll,
    search,
    setSearch,
    filterOp,
    setFilterOp,
    filterEntity,
    setFilterEntity,
    entryLimit,
    loadMore,
    actionMessage,
    actionIsError,
    clearing,
    copyingLog,
    entries,
    filteredEntries,
    opCounts,
    entityTypes,
    copyChangelog,
    handleClearAll,
    undoingEntryId,
    handleUndo,
    refetchChangelog: triggerRefetch,
    dataUpdatedAt,
    isFetching,
    filterOps: FILTER_OPS,
  };
}
