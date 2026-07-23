import { useTaskDetailRelationSearch } from './useTaskDetailRelationSearch';

interface TaskDetailRelationSearchInputProps {
  excludeIds: string[];
  noResultsLabel: string;
  onCancel: () => void;
  onSelect: (taskId: string) => void;
  placeholder: string;
  /**
   * Per-row cycle precheck. When a row would create a
   * dependency cycle, the option is rendered disabled and shows
   * `cycleHintLabel` inline. Callers pass `null` to fall back to no
   * precheck (the server-side validator still rejects cycle edges).
   */
  wouldCreateCycle?: ((taskId: string) => boolean) | null;
  cycleBadgeLabel?: string;
  cycleHintLabel?: string;
}

export function TaskDetailRelationSearchInput({
  excludeIds,
  noResultsLabel,
  onCancel,
  onSelect,
  placeholder,
  wouldCreateCycle,
  cycleBadgeLabel,
  cycleHintLabel,
}: TaskDetailRelationSearchInputProps) {
  const { inputRef, loading, query, results, setQuery } = useTaskDetailRelationSearch({ excludeIds });

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
        placeholder={placeholder}
        aria-label={placeholder}
        className="w-full bg-transparent text-sm text-text-primary outline-hidden focus-ring-soft placeholder:text-text-muted/60"
      />
      {loading && (
        <p className="text-xs text-text-muted">…</p>
      )}
      {results.length > 0 && (
        <ul className="space-y-0.5 max-h-40 overflow-y-auto overscroll-contain">
          {results.map((task) => {
            const cyclic = wouldCreateCycle ? wouldCreateCycle(task.id) : false;
            return (
              <li key={task.id}>
                <button
                  type="button"
                  onClick={() => { if (!cyclic) onSelect(task.id); }}
                  disabled={cyclic}
                  aria-disabled={cyclic || undefined}
                  title={cyclic ? cycleHintLabel : undefined}
                  className={`w-full text-start text-sm rounded-r-control px-2 py-1 focus-ring-soft flex items-center gap-2 ${
                    cyclic
                      ? 'text-text-muted/60 cursor-not-allowed'
                      : 'text-text-secondary hover:text-text-primary hover:bg-surface-3'
                  }`}
                >
                  <span className="flex-1 min-w-0 truncate">{task.title}</span>
                  {cyclic ? (
                    <span className="shrink-0 text-xs chip-warning px-1.5 py-0.5 rounded-r-control">
                      ↺ {cycleBadgeLabel ?? 'cycle'}
                    </span>
                  ) : null}
                </button>
              </li>
            );
          })}
        </ul>
      )}
      {query.length >= 2 && !loading && results.length === 0 && (
        <p className="text-xs text-text-muted px-1">{noResultsLabel}</p>
      )}
    </div>
  );
}
