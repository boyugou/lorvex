import { useCallback, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import type { ChangelogEntry } from '@/lib/ipc/tasks/models';
import { getTaskHistory } from '@/lib/ipc/tasks/reviews';
import { useI18n } from '@/lib/i18n';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { formatRelativeTime } from '@/lib/dates/dateLocale';
import { getUIStateBoolean, setUIState } from '@/lib/storage/uiState';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { CheckIcon, XIcon } from '@/components/ui/icons';
import { CollapsibleSection } from '@/components/ui/CollapsibleSection';

/**
 * collapsible per-task History section inside the task
 * detail panel. Queries `ai_changelog` filtered by this task's
 * `entity_id` and renders the rows with the same visual shape as the
 * global Activity Log (`ChangelogView`). Power users asked for an
 * inline audit trail so debugging "why did this task's priority get
 * bumped and when?" doesn't require leaving the task detail panel.
 *
 * Scope guards:
 * - No undo buttons. Undo lives on the global Activity Log.
 * - No filter chips. This view is already narrowed to one entity.
 * - No clear/copy controls. This is read-only inline context.
 *
 * Data is paged in two steps: the first render shows INITIAL_LIMIT
 * rows (bounded so a very chatty task doesn't bloat the detail
 * panel), and a "Show more" button expands to EXPANDED_LIMIT. Past
 * that, search + infinite scroll live on the global view.
 */
const INITIAL_LIMIT = 20;
const EXPANDED_LIMIT = 200;
const STORAGE_KEY = 'taskDetail:historyExpanded';

export function TaskHistorySection({ taskId }: { taskId: string }) {
  const { t } = useI18n();
  const { timezone } = useConfiguredDayContext();
  const [expanded, setExpanded] = useState(() => getUIStateBoolean(STORAGE_KEY, false));
  const [limit, setLimit] = useState(INITIAL_LIMIT);

  const toggle = useCallback(() => {
    setExpanded((prev) => {
      const next = !prev;
      setUIState(STORAGE_KEY, next);
      return next;
    });
  }, []);

  // The query is keyed under `QK.aiChangelog` so any mutation that
  // invalidates the global Activity Log (via
  // `invalidateChangelogQueries`) also invalidates the per-task
  // history automatically — no extra wiring needed when task writes
  // append new changelog rows.
  const {
    data: entries,
    isLoading,
    isError,
  } = useQuery({
    queryKey: QUERY_KEYS.taskAiChangelog(taskId, limit),
    queryFn: ({ signal }) => getTaskHistory(taskId, limit, signal),
    // Only fetch when the section is expanded — collapsed is the
    // common case, and a global Activity Log that already runs on
    // every detail panel open would be wasteful.
    enabled: expanded,
  });

  const hasEntries = (entries?.length ?? 0) > 0;
  const canShowMore = hasEntries && (entries?.length ?? 0) >= limit && limit < EXPANDED_LIMIT;

  return (
    <div>
      <button
        type="button"
        onClick={toggle}
        aria-expanded={expanded}
        className="group flex items-center gap-2 w-full text-2xs text-text-muted/50 hover:text-text-muted transition-colors duration-150 py-2 px-1 -mx-1 rounded-r-control hover:bg-surface-2/40 focus-ring-soft"
      >
        <svg
          aria-hidden="true"
          className="w-3 h-3 transition-transform duration-200 opacity-40 group-hover:opacity-70"
          style={{ transform: expanded ? 'rotate(90deg)' : 'rotate(0deg)' }}
          viewBox="0 0 16 16"
          fill="currentColor"
        >
          <path
            d="M6 3.5l4.5 4.5L6 12.5"
            stroke="currentColor"
            strokeWidth="1.5"
            fill="none"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
        <span className="font-medium tracking-wide uppercase">{t('taskDetail.history.title')}</span>
      </button>

      <CollapsibleSection collapsed={!expanded}>
        <div className="pt-1 ps-0.5">
          {isLoading ? (
            <p className="text-xs text-text-muted/60 px-2 py-2">{t('taskDetail.history.loading')}</p>
          ) : isError ? (
            <p className="text-xs text-danger/70 px-2 py-2">{t('taskDetail.history.error')}</p>
          ) : !hasEntries ? (
            <p className="text-xs text-text-muted/60 px-2 py-2">{t('taskDetail.history.empty')}</p>
          ) : (
            <>
              <ul className="space-y-0.5">
                {entries!.map((entry) => (
                  <TaskHistoryRow key={entry.id} entry={entry} timezone={timezone} />
                ))}
              </ul>
              {canShowMore && (
                <div className="pt-1.5">
                  <button
                    type="button"
                    onClick={() => setLimit(EXPANDED_LIMIT)}
                    className="text-xs px-3 py-1 rounded-r-control bg-surface-2 text-text-secondary hover:bg-surface-3 transition-colors focus-ring-soft"
                  >
                    {t('taskDetail.history.showMore')}
                  </button>
                </div>
              )}
            </>
          )}
        </div>
      </CollapsibleSection>
    </div>
  );
}

/**
 * Row rendering mirrors `ChangelogView`'s `ChangelogRow` visually but
 * is non-navigating (you're already on the task's detail) and omits
 * the Undo affordance by design ( scope guard — Undo lives on
 * the global Activity Log.).
 */
function TaskHistoryRow({ entry, timezone }: { entry: ChangelogEntry; timezone: string }) {
  const { t, format, locale } = useI18n();
  const icon = OP_ICONS[entry.operation] ?? '\u00B7';
  const color = OP_COLORS[entry.operation] ?? 'text-text-muted';
  const time = formatRelativeTime(entry.timestamp, locale, t, format, timezone);

  return (
    <li className="flex items-start gap-3 px-2 py-1.5 rounded-r-control hover:bg-surface-2/40 transition-colors">
      <span
        className={`w-5 h-5 rounded-r-control bg-surface-3/50 inline-flex items-center justify-center text-xs shrink-0 ${color}`}
      >
        {icon}
      </span>
      <div className="flex-1 min-w-0">
        <p className="text-xs text-text-primary leading-snug select-text-content break-words">{entry.summary}</p>
        <div className="flex items-center gap-2 mt-0.5 text-2xs text-text-muted">
          <span>{time}</span>
          {entry.mcp_tool && (
            <span className="bg-surface-3 px-1.5 py-0.5 rounded-r-control font-mono text-3xs max-w-[10rem] truncate">
              {entry.mcp_tool}
            </span>
          )}
        </div>
      </div>
    </li>
  );
}

const OP_ICONS: Record<string, React.ReactNode> = {
  create: <span className="inline-block w-3 h-3 leading-none text-center font-bold">+</span>,
  update: <span className="inline-block w-3 h-3 leading-none text-center font-medium">~</span>,
  complete: <CheckIcon className="w-3 h-3 inline-block" />,
  delete: <XIcon className="w-3 h-3 inline-block" />,
  triage: <span className="inline-block w-3 h-3 leading-none text-center">{'\u2192'}</span>,
  plan: <span className="inline-block w-3 h-3 leading-none text-center">{'\u25C6'}</span>,
};

const OP_COLORS: Record<string, string> = {
  create: 'text-accent',
  update: 'text-text-secondary',
  complete: 'text-success',
  delete: 'text-danger',
  triage: 'text-warning',
  plan: 'text-accent',
};
