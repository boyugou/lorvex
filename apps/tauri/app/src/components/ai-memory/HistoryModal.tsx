import { useQuery } from '@tanstack/react-query';
import { getMemoryHistory, type MemoryRevisionEntry } from '@/lib/ipc/memory';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import type { TranslationKey } from '@/lib/i18n';
import { Modal } from '../ui/Modal';
import { RevisionRow } from './RevisionRow';
import { formatKey } from './helpers';
import { useRestoreMemoryRevisionAction } from './useAiMemoryActions';

export function HistoryModal({
  memoryKey,
  locale,
  timezone,
  t,
  onClose,
  onMutate,
}: {
  memoryKey: string;
  locale: string;
  timezone: string;
  t: (k: TranslationKey) => string;
  onClose: () => void;
  onMutate: () => void;
}) {
  const { data, isLoading, isError } = useQuery({
    queryKey: QUERY_KEYS.memoryHistory(memoryKey),
    queryFn: ({ signal }) => getMemoryHistory(memoryKey, 50, signal),
  });
  // hook owns invalidation via
  // `invalidateQueriesForEntity('memory_revision')`; `onSuccess`
  // forwards the caller's notifier (parent uses it to coordinate UI).
  const restoreMutation = useRestoreMemoryRevisionAction({ onSuccess: onMutate, t });

  const operationLabel = (op: string): string => {
    switch (op) {
      case 'upsert': return t('memory.revision.upsert');
      case 'delete': return t('memory.revision.delete');
      case 'restore': return t('memory.revision.restore');
      default: return op;
    }
  };

  const actorLabel = (actor: string): string => {
    return actor === 'ai' ? t('memory.revision.byAi') : t('memory.revision.byHuman');
  };

  const operationColor = (op: string): string => {
    switch (op) {
      case 'delete': return 'text-danger';
      case 'restore': return 'text-accent';
      default: return 'text-text-secondary';
    }
  };

  return (
    <Modal
      open
      onClose={onClose}
      size="lg"
      panelClassName="mx-4 max-h-[80vh] flex flex-col"
      ariaLabel={`${t('memory.historyTitle')} — ${formatKey(memoryKey)}`}
    >
      <div className="px-5 py-4 border-b border-card shrink-0">
        <h3 className="text-text-primary text-sm font-semibold">
          {t('memory.historyTitle')} — {formatKey(memoryKey)}
        </h3>
      </div>

      <div className="flex-1 overflow-y-auto overscroll-contain px-5 py-3 space-y-3">
        {isLoading ? (
          <div className="space-y-3 py-4 animate-pulse">
            <div className="h-4 w-3/4 rounded-r-control bg-surface-2 mx-auto" />
            <div className="h-4 w-1/2 rounded-r-control bg-surface-2 mx-auto" />
          </div>
        ) : isError ? (
          <div className="text-center text-danger py-8">{t('memory.historyLoadError')}</div>
        ) : !data || data.revisions.length === 0 ? (
          <div className="text-text-muted text-sm text-center py-6">{t('memory.noHistory')}</div>
        ) : (
          data.revisions.map((rev: MemoryRevisionEntry) => (
            <RevisionRow
              key={rev.id}
              revision={rev}
              locale={locale}
              timezone={timezone}
              t={t}
              operationLabel={operationLabel}
              actorLabel={actorLabel}
              operationColor={operationColor}
              onRestore={(id) => restoreMutation.mutate(id)}
              // Per-row gating: only the row whose revision id is the
              // in-flight mutation variable should appear restoring or
              // be disabled. The previous global flag put every row in
              // a visually-restoring state and let a stray Enter on a
              // different row queue a second restore once the first
              // landed (mirrors `isPendingForHabit`).
              restoring={restoreMutation.isPending && restoreMutation.variables === rev.id}
            />
          ))
        )}
      </div>

      <div className="px-5 py-3 border-t border-card shrink-0 flex justify-end">
        <button
          type="button"
          onClick={onClose}
          className="rounded-r-control border border-card bg-surface-2/50 text-text-secondary text-xs font-medium px-3 py-1.5 hover:bg-surface-3/60 transition-colors focus-ring-strong"
        >
          {t('common.close')}
        </button>
      </div>
    </Modal>
  );
}
