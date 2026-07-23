import { useI18n } from '../lib/i18n';
import { formatPageTitle } from '../lib/pageTitle';
import { useConfiguredDayContext } from '../lib/dayContext';
import { formatRelativeTime } from '../lib/dates/dateLocale';
import { useMcpServerStatus } from '../lib/hooks/useMcpServerStatus';
import type { TranslationKey } from '../lib/i18n';
import type { ChangelogEntry } from '@/lib/ipc/tasks/models';
import type { View } from '../lib/types';
import AssistantNotConfiguredPanel from './ui/AssistantNotConfiguredPanel';
import { CheckIcon, SearchIcon, SparkleIcon, XIcon } from './ui/icons';
import ModuleStatePanel from './ui/ModuleStatePanel';
import { SearchInput } from './ui/SearchInput';
import { Tooltip } from './ui/Tooltip';
import { ToggleChip } from './ui/ToggleChip';
import { TonalButton } from './ui/TonalButton';
import { useChangelogController } from './changelog/useChangelogController';

/**
 * Translation keys for each `ai_changelog.operation` enum value, mirroring
 * the `ENTITY_TYPE_KEYS` pattern. Without this map the changelog renders
 * the raw English enum string (`create`, `update`, …) inside a localized
 * page, so a Chinese-locale user sees a mix of "更新" and literal
 * `update`.
 */
const OP_LABEL_KEYS: Record<string, TranslationKey> = {
  create: 'changelog.opCreate',
  update: 'changelog.opUpdate',
  complete: 'changelog.opComplete',
  delete: 'changelog.opDelete',
  triage: 'changelog.opTriage',
  plan: 'changelog.opPlan',
};

const ENTITY_TYPE_KEYS: Record<string, TranslationKey> = {
  task: 'entityType.task',
  list: 'entityType.list',
  preference: 'entityType.preference',
  current_focus: 'entityType.current_focus',
  daily_review: 'entityType.daily_review',
  calendar_event: 'entityType.calendar_event',
  task_calendar_event_link: 'entityType.task_calendar_event_link',
  memory: 'entityType.memory',
  habit: 'entityType.habit',
  habit_completion: 'entityType.habit_completion',
  focus_schedule: 'entityType.focus_schedule',
};

interface ChangelogViewProps {
  onSelectTask?: ((taskId: string) => void) | undefined;
  /**
   * forwarded from MainViewContent so the empty-state
   * "Connect your AI assistant" card can deep-link into Settings →
   * Assistant MCP when `mcpServerStatus.resolved === false`.
   */
  onNavigate?: ((view: View) => void) | undefined;
}

export default function ChangelogView({ onSelectTask, onNavigate }: ChangelogViewProps) {
  const {
    t,
    format,
    scroll,
    search,
    setSearch,
    filterOp,
    setFilterOp,
    filterEntity,
    setFilterEntity,
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
    loadMore,
    entryLimit,
    filterOps,
    refetchChangelog,
    dataUpdatedAt,
    isFetching,
  } = useChangelogController();
  const { timezone } = useConfiguredDayContext();
  const { locale } = useI18n();
  const mcpStatus = useMcpServerStatus();
  // only replace the generic "nothing logged yet" copy
  // with the setup CTA when we have a confirmed `resolved: false`
  // answer from the backend. While the query is still fetching or on
  // mobile runtimes that do not host MCP, fall through to the normal
  // empty state so we don't flash a misleading "connect your AI
  // assistant" card at a user who already has one working.
  const mcpUnconfigured = mcpStatus !== null && mcpStatus.resolved === false;
  const lastFetchedLabel = formatRelativeTime(
    new Date(dataUpdatedAt).toISOString(),
    locale,
    t,
    format,
    timezone,
  );

  return (
    <div className="h-full flex flex-col overflow-hidden">
      <title>{formatPageTitle(t('nav.changelog'))}</title>
      <header className="px-4 sm:px-8 pt-1.5 pb-5 shrink-0">
        <p className="text-text-muted text-xs font-medium mb-1">{t('nav.changelog')}</p>
        <h2 className="text-text-primary text-2xl font-light">{t('changelog.title')}</h2>
        <p className="text-text-muted text-xs mt-2">{t('changelog.subtitle')}</p>
        {entries.length > 0 && (
          <div className="flex items-center gap-1.5 mt-3 flex-wrap">
            <ToggleChip
              size="xs"
              onClick={() => setFilterOp(null)}
              selected={filterOp === null}
              inactiveClassName="bg-surface-2 text-text-muted hover:text-text-primary"
            >
              {t('changelog.filterAll')} ({entries.length})
            </ToggleChip>
            {filterOps.map(op => {
              const count = opCounts[op] ?? 0;
              if (count === 0) return null;
              return (
                <ToggleChip
                  size="xs"
                  key={op}
                  onClick={() => setFilterOp(filterOp === op ? null : op)}
                  selected={filterOp === op}
                  inactiveClassName="bg-surface-2 text-text-muted hover:text-text-primary"
                >
                  {OP_ICONS[op]} {OP_LABEL_KEYS[op] ? t(OP_LABEL_KEYS[op]!) : op} ({count})
                </ToggleChip>
              );
            })}
          </div>
        )}
        {entityTypes.length > 1 && (
          <div className="flex items-center gap-1.5 mt-2 flex-wrap">
            <ToggleChip
              size="xs"
              onClick={() => setFilterEntity(null)}
              selected={filterEntity === null}
              inactiveClassName="bg-surface-2 text-text-muted hover:text-text-primary"
            >
              {t('changelog.entityAll')}
            </ToggleChip>
            {entityTypes.map(([type, count]) => (
              <ToggleChip
                size="xs"
                key={type}
                onClick={() => setFilterEntity(filterEntity === type ? null : type)}
                selected={filterEntity === type}
                inactiveClassName="bg-surface-2 text-text-muted hover:text-text-primary"
              >
                {/* Capitalize only the raw entity-type fallback; a localized
                    label is already correctly cased and must not be force-cased
                    (wrong for locales where the leading word stays lowercase). */}
                {ENTITY_TYPE_KEYS[type] ? t(ENTITY_TYPE_KEYS[type]) : <span className="capitalize">{type}</span>} ({count})
              </ToggleChip>
            ))}
          </div>
        )}
        {entries.length > 0 && (
          <div className="flex items-center gap-2 mt-3">
            <SearchInput value={search} onChange={setSearch} placeholder={t('changelog.searchPlaceholder')} className="relative flex-1 max-w-sm" />
            <button
              type="button"
              onClick={() => { void copyChangelog(); }}
              disabled={copyingLog}
              className="text-xs px-2.5 py-1.5 rounded-r-card bg-surface-2 text-text-secondary hover:bg-surface-3 disabled:opacity-50 disabled:cursor-not-allowed focus-ring-soft"
            >
              {t('changelog.copyChangelog')}
            </button>
            <TonalButton
              tone="danger"
              size="lg"
              onClick={() => { void handleClearAll(); }}
              disabled={clearing}
            >
              {t('changelog.clearAll')}
            </TonalButton>
          </div>
        )}
        {actionMessage && (
          <p className={`text-xs mt-2 break-all ${actionIsError ? 'text-danger' : 'text-text-muted'}`}>{actionMessage}</p>
        )}
      </header>

      <div ref={scroll.ref} onScroll={scroll.onScroll} className="flex-1 overflow-y-auto overscroll-contain px-4 sm:px-8 pb-8">
        {entries.length === 0 ? (
          // first fork — if MCP isn't configured, surface the
          // setup CTA instead of "your AI will log here" since the
          // user has nothing to wait for.: otherwise distinguish
          // "ready, nothing logged" from "stale cache" by surfacing
          // when this view last got fresh data and a Refresh
          // affordance. First-run users see the freshness line too —
          // harmless — but users who open this view days later can
          // tell whether the DB actually has no AI writes vs the
          // query hasn't re-run.
          mcpUnconfigured ? (
            <AssistantNotConfiguredPanel onNavigate={onNavigate} />
          ) : (
            <div className="flex flex-col items-center justify-center py-12 sm:py-20 text-center" role="status" aria-live="polite">
              <div className="mb-4 text-text-muted/60"><SparkleIcon className="w-9 h-9" /></div>
              <p className="text-text-secondary text-sm font-medium">{t('changelog.empty')}</p>
              <p className="text-text-muted text-xs mt-1.5 max-w-[26rem] leading-relaxed">
                {t('changelog.emptyHint')} · {t('changelog.lastRefreshed')} {lastFetchedLabel}
              </p>
              <button
                type="button"
                onClick={refetchChangelog}
                disabled={isFetching}
                className="mt-5 text-xs px-4 py-2 rounded-r-control border border-card text-text-secondary hover:bg-surface-2 hover:border-popover active:scale-[0.97] disabled:opacity-50 transition-[color,background-color,border-color,transform] focus-ring-strong"
              >
                {isFetching ? t('changelog.refreshing') : t('changelog.refresh')}
              </button>
              {/* "Try saying" prompt block — pairs the empty state with
                  a copyable example phrase the user can repeat back to
                  their assistant. Matches the WelcomeView
                  exampleTaskPrompt pattern so the muscle memory of
                  "talk to the assistant in plain English" surfaces in
                  the only other place a first-run user is likely to
                  land before any AI writes exist. */}
              <div className="mt-7 w-full max-w-md rounded-r-card border border-surface-3 bg-surface-1 p-4 text-start">
                <p className="text-text-muted/80 text-2xs font-semibold tracking-widest uppercase mb-2">
                  {t('changelog.tryEyebrow')}
                </p>
                <p className="text-text-secondary text-xs leading-relaxed">
                  {t('changelog.tryIntro')}{' '}
                  <span className="font-mono text-text-primary bg-surface-2/80 rounded-r-control px-1.5 py-0.5 mx-0.5 inline-block">
                    {t('changelog.tryPrompt')}
                  </span>
                </p>
              </div>
            </div>
          )
        ) : filteredEntries.length === 0 ? (
          <ModuleStatePanel icon={<SearchIcon className="w-9 h-9" />} title={t('changelog.noMatches')} />
        ) : (
          <>
            <div className="space-y-0.5">
              {filteredEntries.map(entry => (
                <ChangelogRow
                  key={entry.id}
                  entry={entry}
                  onSelectTask={onSelectTask}
                  timezone={timezone}
                  onUndo={handleUndo}
                  undoing={undoingEntryId === entry.id}
                />
              ))}
            </div>
            {entries.length >= entryLimit && (
              <div className="flex justify-center pt-4">
                <button
                  type="button"
                  onClick={loadMore}
                  className="text-xs px-4 py-1.5 rounded-r-card bg-surface-2 text-text-secondary hover:bg-surface-3 transition-colors focus-ring-soft"
                >
                  {t('changelog.loadMore')}
                </button>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}

const OP_ICONS: Record<string, React.ReactNode> = {
  create: <span className="inline-block w-3.5 h-3.5 leading-none text-center font-bold">+</span>,
  update: <span className="inline-block w-3.5 h-3.5 leading-none text-center font-medium">~</span>,
  complete: <CheckIcon className="w-3.5 h-3.5 inline-block" />,
  delete: <XIcon className="w-3.5 h-3.5 inline-block" />,
  triage: <span className="inline-block w-3.5 h-3.5 leading-none text-center">{'\u2192'}</span>,
  plan: <span className="inline-block w-3.5 h-3.5 leading-none text-center">{'\u25C6'}</span>,
};

const OP_COLORS: Record<string, string> = {
  create: 'text-accent',
  update: 'text-text-secondary',
  complete: 'text-success',
  delete: 'text-danger',
  triage: 'text-warning',
  plan: 'text-accent',
};

function ChangelogRow({
  entry,
  onSelectTask,
  timezone,
  onUndo,
  undoing,
}: {
  entry: ChangelogEntry;
  onSelectTask?: ((taskId: string) => void) | undefined;
  timezone: string;
  onUndo: (entry: ChangelogEntry) => Promise<void>;
  undoing: boolean;
}) {
  const { t, format, locale } = useI18n();
  const icon = OP_ICONS[entry.operation] ?? '\u00B7';
  const color = OP_COLORS[entry.operation] ?? 'text-text-muted';
  const time = formatRelativeTime(entry.timestamp, locale, t, format, timezone);
  const canNavigate = entry.entity_id && entry.entity_type === 'task' && onSelectTask;
  // render the per-row Undo affordance only when the
  // backend has attached a non-null undo_token (i.e. the matching
  // sync_outbox row is still inside its 5-second hold AND the cached
  // serialized token survived this session). The button intentionally
  // lives on every eligible row regardless of navigation — the 5s
  // window ticks on its own.
  const canUndo = Boolean(entry.undo_token);

  // Undo button is rendered as a sibling to the main row body so a
  // click on it doesn't bubble to the navigation button / div. We
  // nest it in a wrapper `div` and the navigable main area as a
  // separate button/div to avoid nesting interactive elements.
  const undoButton = canUndo ? (
    <Tooltip label={t('changelog.undoThis')}>
      <span className="inline-flex">
        <button
          type="button"
          onClick={(e) => {
            e.stopPropagation();
            void onUndo(entry);
          }}
          disabled={undoing}
          aria-label={t('changelog.undoThis')}
          // prior `px-2 py-0.5` left the button at
          // ~16-18 px tall — below the WCAG 2.5.5 24×24 minimum hit
          // target. Bump padding to land at ≥24 px while leaving the
          // text-xs label visually identical.
          className="text-xs px-2.5 py-1.5 rounded-r-control bg-surface-3 text-text-secondary hover:bg-accent/15 hover:text-accent disabled:opacity-50 disabled:cursor-wait transition-colors focus-ring-soft"
        >
          {t('common.undo')}
        </button>
      </span>
    </Tooltip>
  ) : null;

  const body = (
    <>
      <span className={`w-6 h-6 rounded-r-control bg-surface-3/50 inline-flex items-center justify-center text-sm shrink-0 ${color}`}>
        {icon}
      </span>
      <div className="flex-1 min-w-0">
        <p className="text-sm text-text-primary leading-normal select-text-content">{entry.summary}</p>
        <div className="flex items-center gap-2 mt-1 text-xs text-text-muted">
          <span>{time}</span>
          {entry.mcp_tool && (
            <span className="bg-surface-3 px-1.5 py-0.5 rounded-r-control font-mono text-xs max-w-[12rem] truncate">
              {entry.mcp_tool}
            </span>
          )}
          <span>{ENTITY_TYPE_KEYS[entry.entity_type] ? t(ENTITY_TYPE_KEYS[entry.entity_type]!) : entry.entity_type}</span>
        </div>
      </div>
    </>
  );

  return (
    <div className="cv-changelog-row flex items-center gap-2 pe-3 rounded-r-card hover:bg-surface-2 transition-colors">
      {canNavigate ? (
        <button
          type="button"
          className="flex-1 min-w-0 flex items-start gap-3 px-4 py-2.5 text-start cursor-pointer focus-ring-soft rounded-r-card"
          onClick={() => onSelectTask(entry.entity_id!)}
        >
          {body}
        </button>
      ) : (
        <div className="flex-1 min-w-0 flex items-start gap-3 px-4 py-2.5">
          {body}
        </div>
      )}
      {undoButton}
    </div>
  );
}
