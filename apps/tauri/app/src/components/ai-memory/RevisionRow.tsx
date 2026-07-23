import type { MemoryRevisionEntry } from '@/lib/ipc/memory';
import { useI18n, type TranslationKey } from '@/lib/i18n';
import { formatRelativeTime } from '@/lib/dates/dateLocale';
import { UndoIcon } from '../ui/icons';

export function RevisionRow({
  revision,
  locale,
  timezone,
  t,
  operationLabel,
  actorLabel,
  operationColor,
  onRestore,
  restoring,
}: {
  revision: MemoryRevisionEntry;
  locale: string;
  timezone: string;
  t: (k: TranslationKey) => string;
  operationLabel: (op: string) => string;
  actorLabel: (actor: string) => string;
  operationColor: (op: string) => string;
  onRestore: (revisionId: string) => void;
  restoring: boolean;
}) {
  const { format } = useI18n();
  return (
    <div className="bg-surface-2 border border-surface-3 rounded-r-card p-3">
      <div className="flex items-center justify-between mb-1.5">
        <div className="flex items-center gap-2">
          <span className={`text-xs font-medium ${operationColor(revision.operation)}`}>
            {operationLabel(revision.operation)}
          </span>
          <span className="text-text-muted text-xs">
            {actorLabel(revision.actor)}
          </span>
        </div>
        <div className="flex items-center gap-2">
          <span className="text-text-muted text-xs">
            {formatRelativeTime(revision.created_at, locale, t, format, timezone)}
          </span>
          {revision.content != null && (
            <button
              type="button"
              onClick={() => onRestore(revision.id)}
              disabled={restoring}
              className="text-accent hover:text-accent/80 text-xs px-1.5 py-0.5 rounded-r-control hover:bg-accent/10 transition-colors flex items-center gap-1 disabled:opacity-50 focus-ring-soft"
            >
              <UndoIcon className="w-3 h-3" />
              {t('memory.restore')}
            </button>
          )}
        </div>
      </div>
      {revision.content != null && (
        <div className="text-text-secondary text-xs leading-relaxed whitespace-pre-wrap line-clamp-4 select-text-content">
          {revision.content}
        </div>
      )}
    </div>
  );
}
