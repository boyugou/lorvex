import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import type { TranslationKey } from '@/lib/i18n';
import { useTaskDetailEventLinkSearch } from './useTaskDetailEventLinkSearch';

interface TaskDetailEventLinkSearchInputProps {
  excludeIds: string[];
  onCancel: () => void;
  onSelect: (event: UnifiedCalendarEvent) => void;
  t: (key: TranslationKey) => string;
}

export function TaskDetailEventLinkSearchInput({
  excludeIds,
  onCancel,
  onSelect,
  t,
}: TaskDetailEventLinkSearchInputProps) {
  const { inputRef, query, results, setQuery } = useTaskDetailEventLinkSearch({ excludeIds });

  return (
    <div className="rounded-r-control border border-surface-3 bg-surface-2/60 p-2 space-y-1.5">
      {/* search type for SR + soft-keyboard. */}
      <input
        ref={inputRef}
        type="search"
        value={query}
        onChange={(event) => setQuery(event.target.value)}
        onKeyDown={(event) => {
          if (event.key === 'Escape') onCancel();
        }}
        placeholder={t('task.searchEvents')}
        aria-label={t('task.searchEvents')}
        className="w-full bg-transparent text-sm text-text-primary outline-hidden focus-ring-soft placeholder:text-text-muted/60"
      />
      {results.length > 0 ? (
        <ul className="space-y-0.5 max-h-40 overflow-y-auto overscroll-contain">
          {results.map((event) => (
            <li key={`${event.id}-${event.start_date}`}>
              <button
                type="button"
                onClick={() => onSelect(event)}
                className="w-full text-start text-sm text-text-secondary hover:text-text-primary hover:bg-surface-3 rounded-r-control px-2 py-1 truncate focus-ring-soft"
              >
                <span>{event.title}</span>
                <span className="text-xs text-text-muted ms-2">
                  {event.start_date}
                  {event.start_time ? ` ${event.start_time}` : ''}
                </span>
                {event.kind === 'provider' && (
                  <span className="text-3xs text-text-muted/60 ms-1.5">({t('task.providerEventBadge')})</span>
                )}
              </button>
            </li>
          ))}
        </ul>
      ) : null}
      {query.length >= 2 && results.length === 0 && (
        <p className="text-xs text-text-muted px-1">{t('common.noResults')}</p>
      )}
    </div>
  );
}
