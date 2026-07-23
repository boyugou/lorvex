import { type MouseEvent as ReactMouseEvent, type Ref } from 'react';
import { BulkActionBar } from './ui/BulkActionBar';
import { Button } from './ui/Button';
import { PickerOverlays } from './ui/PickerOverlays';
import { InteractiveTaskCard } from './task-card/InteractiveTaskCard';
import { CollapsibleSection } from './ui/CollapsibleSection';
import { ChevronDownIcon, SearchIcon, ThoughtBubbleIcon, WarningIcon } from './ui/icons';
import ModuleStatePanel from './ui/ModuleStatePanel';
import { StaleDataBanner } from './ui/StaleDataBanner';
import { ViewToolbar } from './ui/ViewToolbar';
import { SavedQueriesMenu } from './ui/SavedQueriesMenu';
import { KeyboardHintBar } from './ui/KeyboardHintBar';
import { SomedayViewSkeleton } from './someday/SomedayViewSkeleton';
import { useSomedayController } from './someday/useSomedayController';
import type { SomedaySortKey, GroupBy, SomedaySection } from './someday/grouping';
import {
  deserializeViewFilters,
  readSavedFilterEnum,
  serializeViewFilters,
} from '../lib/tasks/savedFilterShape';
import { useI18n, type TranslationKey } from '../lib/i18n';
import { formatPageTitle } from '../lib/pageTitle';
import type { QuickCaptureInitialData } from '../app-shell/main-window/types';
import { isImeComposing } from '@/lib/ime';

/**
 * Empty-state templates for the Someday view. Surfaced as CTA chips
 * alongside the "Park an idea" primary action so a user landing on
 * Someday with zero tasks discovers what the surface is for ("a
 * graveyard for raw ideas") rather than guessing from the title. The
 * `title` we pre-fill into QuickCapture is the user-facing label
 * itself — the user can edit it or commit as-is.
 */
const SOMEDAY_TEMPLATES: ReadonlyArray<{
  key: 'travel' | 'books' | 'learn';
  labelKey: TranslationKey;
}> = [
  { key: 'travel', labelKey: 'someday.template.travel' },
  { key: 'books', labelKey: 'someday.template.books' },
  { key: 'learn', labelKey: 'someday.template.learn' },
];

interface Props {
  onSelectTask?: ((taskId: string) => void) | undefined;
  /**
   * Opens QuickCapture so the empty-state "Park an idea" CTA lands the
   * user on the capture form with a fresh blank entry. The form's
   * status defaults route the captured task back through the normal
   * routing logic; pre-setting `status: 'someday'` here is unnecessary
   * because the someday inline-add path already drives that via
   * `controller.handleAddSomeday`.
   */
  onOpenQuickCapture?: ((data?: QuickCaptureInitialData) => void) | undefined;
}

export default function SomedayView({ onSelectTask, onOpenQuickCapture }: Props) {
  const controller = useSomedayController({ onSelectTask });
  const { formatNumber } = useI18n();
  const { t } = controller;

  return (
    <div className="h-full flex flex-col overflow-hidden">
      <title>{formatPageTitle(t('nav.someday'))}</title>
      <header className="px-4 sm:px-8 pt-1.5 pb-5 shrink-0">
        <div className="flex items-baseline justify-between">
          <div>
            <div className="flex items-center gap-2.5">
              <h2 className="text-text-primary text-2xl font-light">{t('someday.title')}</h2>
              {controller.tasks.length > 0 && (
                <span className="chip-tight text-2xs font-medium text-text-muted/60 bg-surface-2/60 tabular-nums">
                  {formatNumber(controller.tasks.length)}
                </span>
              )}
            </div>
            <p className="text-text-muted/70 text-xs mt-2 leading-relaxed">
              {t('someday.subtitle')}
            </p>
          </div>
          {controller.filtered.length > 0 && (
            <Button
              variant="outline"
              onClick={() => controller.setSelectionModeEnabled(!controller.selectionMode)}
              disabled={controller.bulk.bulkAction !== null}
            >
              {controller.selectionMode ? t('common.done') : t('allTasks.select')}
            </Button>
          )}
        </div>

        {controller.tasks.length > 0 && (
          <ViewToolbar<SomedaySortKey, GroupBy>
            search={{ value: controller.search, onChange: controller.setSearch, placeholder: t('someday.search') }}
            sort={{
              value: controller.sortKey,
              options: controller.sortKeys.map((key) => ({ value: key, label: controller.sortLabels[key] })),
              onChange: controller.setSortKey,
            }}
            group={{
              label: t('someday.groupBy'),
              value: controller.groupBy,
              options: controller.groupByKeys.map((key) => ({ value: key, label: controller.groupByLabels[key] })),
              onChange: controller.setGroupBy,
            }}
            filterList={{ lists: controller.lists, value: controller.filterListId, onChange: controller.setFilterListId }}
            filterPriority={{ value: controller.filterPriority, onChange: controller.setFilterPriority }}
            filterTag={{ available: controller.allTags, selected: controller.selectedTags, onToggle: controller.toggleTag, onClear: controller.clearTagFilter }}
            trailing={
              <SavedQueriesMenu
                viewType="Someday"
                onCapture={() =>
                  serializeViewFilters({
                    search: controller.search,
                    filterListId: controller.filterListId,
                    filterPriority: controller.filterPriority,
                    selectedTags: controller.selectedTags,
                    groupBy: controller.groupBy,
                    sortKey: controller.sortKey,
                  })
                }
                onApply={(filterJson) => {
                  const decoded = deserializeViewFilters(filterJson);
                  controller.setSearch(decoded.search ?? '');
                  controller.setFilterListId(decoded.listId ?? null);
                  controller.setFilterPriority(decoded.priority ?? null);
                  controller.replaceSelectedTags(decoded.tags ?? []);
                  const nextGroupBy = readSavedFilterEnum(decoded.groupBy, controller.groupByKeys);
                  if (nextGroupBy) controller.setGroupBy(nextGroupBy);
                  const nextSortKey = readSavedFilterEnum(decoded.sortKey, controller.sortKeys);
                  if (nextSortKey) controller.setSortKey(nextSortKey);
                }}
              />
            }
          />
        )}

        {controller.selectionMode && (
          <BulkActionBar
            selectedCount={controller.bulk.selectedCount}
            bulkAction={controller.bulk.bulkAction}
            onSelectAll={controller.selectAll}
            onClearSelection={() => controller.setSelectedIds(new Set())}
            onComplete={() => void controller.bulk.handleBulkComplete()}
            onDefer={() => void controller.bulk.handleBulkDefer()}
            onCancel={() => void controller.bulk.handleBulkCancel()}
            onMove={(listId) => void controller.bulk.handleBulkMove(listId)}
          />
        )}
      </header>

      <div ref={controller.scroll.ref} onScroll={controller.scroll.onScroll} className="flex-1 overflow-y-auto overscroll-contain px-4 sm:px-8 pb-8">
        {/* non-blocking banner when cached data is
            visible but a background refetch failed. */}
        {controller.isError && controller.tasks.length > 0 && (
          <StaleDataBanner t={t} onRetry={controller.refetch} />
        )}
        {controller.isLoading ? (
          <SomedayViewSkeleton />
        ) : controller.isError && controller.tasks.length === 0 ? (
          <ModuleStatePanel
            variant="error"
            icon={<WarningIcon className="w-9 h-9" />}
            title={t('common.error')}
            actionLabel={t('error.tryAgain')}
            onAction={controller.refetch}
          />
        ) : controller.tasks.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-12 sm:py-24 text-center" role="status" aria-live="polite">
            <div className="mb-4 text-text-muted/60"><ThoughtBubbleIcon className="w-9 h-9" /></div>
            <p className="text-text-secondary text-sm font-medium">{t('someday.empty')}</p>
            <p className="text-text-muted text-xs mt-1.5 max-w-[26rem] leading-relaxed">{t('someday.emptyHint')}</p>
            {onOpenQuickCapture && (
              <>
                <button
                  type="button"
                  onClick={() => onOpenQuickCapture()}
                  className="mt-6 text-xs px-4 py-2 rounded-r-control bg-accent text-on-accent active:scale-[0.97] hover:bg-accent/90 transition-[color,background-color,transform] duration-150 focus-ring-strong"
                >
                  + {t('someday.parkIdea')}
                </button>
                <div className="mt-5 flex flex-col items-stretch sm:flex-row sm:items-center gap-2 max-w-md w-full">
                  {SOMEDAY_TEMPLATES.map((tpl, idx) => (
                    <button
                      key={tpl.key}
                      type="button"
                      onClick={() => onOpenQuickCapture({ title: t(tpl.labelKey) })}
                      className="group flex-1 rounded-r-card border border-card bg-surface-2/40 px-3.5 py-2.5 text-start hover:border-accent/30 hover:bg-surface-2 active:scale-[0.98] transition-[color,background-color,border-color,transform] duration-150 focus-ring-soft motion-safe:animate-[fade-in_0.3s_ease-out_both]"
                      style={{ animationDelay: `${idx * 60}ms` }}
                    >
                      <span className="block text-xs font-medium text-text-primary">{t(tpl.labelKey)}</span>
                      <span className="block text-2xs text-text-muted mt-0.5 group-hover:text-accent transition-colors">+ {t('someday.templateCtaLabel')}</span>
                    </button>
                  ))}
                </div>
              </>
            )}
          </div>
        ) : controller.filtered.length === 0 ? (
          <ModuleStatePanel icon={<SearchIcon className="w-9 h-9" />} title={t('common.noResults')} />
        ) : controller.groupBy === 'none' ? (
          <div className="space-y-1.5">
            {controller.filtered.map(task => (
              <InteractiveTaskCard
                key={task.id}
                task={task}
                selectionMode={controller.selectionMode}
                selected={controller.selectedIds.has(task.id)}
                bulkBusy={controller.bulk.bulkAction !== null}
                focused={controller.keyboard.focusedId === task.id}
                hasSelection={controller.selectedIds.size > 0}
                onToggleSelected={controller.toggleTaskSelected}
                onSelect={(id) => onSelectTask?.(id)}
                onClickWithModifiers={controller.onClickWithModifiers}
              />
            ))}
            {!controller.selectionMode && <InlineAddForm ref={controller.addInputRef} adding={controller.adding} onSubmit={controller.handleAddSomeday} label={t('someday.addTask')} />}
          </div>
        ) : (
          <div className="space-y-6">
            {controller.sections.map((section) => (
              <SomedaySectionGroup
                key={section.key}
                section={section}
                collapsed={controller.collapsedSections.has(section.key)}
                onToggleCollapse={() => controller.toggleSection(section.key)}
                selectionMode={controller.selectionMode}
                selectedIds={controller.selectedIds}
                bulkBusy={controller.bulk.bulkAction !== null}
                focusedTaskId={controller.keyboard.focusedId}
                onToggleSelected={controller.toggleTaskSelected}
                onSelectTask={onSelectTask}
                onClickWithModifiers={controller.onClickWithModifiers}
              />
            ))}
            {!controller.selectionMode && <InlineAddForm ref={controller.addInputRef} adding={controller.adding} onSubmit={controller.handleAddSomeday} label={t('someday.addTask')} />}
          </div>
        )}
        <KeyboardHintBar visible={controller.keyboard.showKeyboardHints} />
      </div>

      <PickerOverlays
        tasks={controller.allFlatTasks}
        movePickerTaskId={controller.actions.movePickerTaskId}
        closeMovePickerAction={controller.actions.closeMovePickerAction}
        recurrencePickerTaskId={controller.actions.recurrencePickerTaskId}
        closeRecurrencePickerAction={controller.actions.closeRecurrencePickerAction}
        dueDatePickerTaskId={controller.actions.dueDatePickerTaskId}
        closeDueDatePickerAction={controller.actions.closeDueDatePickerAction}
        durationPickerTaskId={controller.actions.durationPickerTaskId}
        closeDurationPickerAction={controller.actions.closeDurationPickerAction}
      />
    </div>
  );
}

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function InlineAddForm({ adding, onSubmit, label, ref }: { adding: boolean; onSubmit: () => Promise<void>; label: string; ref?: Ref<HTMLInputElement> }) {
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        void onSubmit();
      }}
      className="mt-2"
    >
      <input
        ref={ref}
        type="text"
        disabled={adding}
        placeholder={`+ ${label}`}
        aria-label={label}
        className="w-full text-xs bg-transparent text-text-muted hover:text-text-secondary focus:text-text-primary px-4 py-1.5 rounded-r-card border border-transparent hover:border-surface-3 outline-hidden focus-ring-soft placeholder:text-text-muted/70 disabled:opacity-50 transition-colors"
        onKeyDown={(e) => {
          if (e.key === 'Escape' && !isImeComposing(e)) {
            e.currentTarget.blur();
          }
        }}
      />
    </form>
  );
}

function SomedaySectionGroup({
  section,
  collapsed,
  onToggleCollapse,
  selectionMode,
  selectedIds,
  bulkBusy,
  focusedTaskId,
  onToggleSelected,
  onSelectTask,
  onClickWithModifiers,
}: {
  section: SomedaySection;
  collapsed: boolean;
  onToggleCollapse: () => void;
  selectionMode: boolean;
  selectedIds: Set<string>;
  bulkBusy: boolean;
  focusedTaskId: string | null;
  onToggleSelected: (taskId: string) => void;
  onSelectTask?: ((taskId: string) => void) | undefined;
  onClickWithModifiers: (id: string, event: ReactMouseEvent<HTMLButtonElement>) => void;
}) {
  const { formatNumber } = useI18n();
  return (
    <section>
      <h2 className="mb-2.5">
        <button
          type="button"
          className="flex items-center gap-2 select-none focus-ring-soft rounded-r-card text-start py-1 px-2 -ms-2 hover:bg-surface-2/50 transition-colors"
          onClick={onToggleCollapse}
          aria-expanded={!collapsed}
        >
          {/* Chevron is purely decorative — the
              expand/collapse state is conveyed by the parent
              button's `aria-expanded`. Hide from AT to avoid SR
              spelling out "black-down-pointing-triangle". */}
          <ChevronDownIcon aria-hidden="true" className={`w-2.5 h-2.5 text-text-muted transition-transform duration-150 ${collapsed ? '-rotate-90' : ''}`} />
          <span className="text-text-secondary text-xs font-semibold truncate max-w-[280px]">{section.title}</span>
          <span className="text-text-muted/60 text-2xs tabular-nums bg-surface-2/50 px-1.5 py-px rounded-r-control">{formatNumber(section.tasks.length)}</span>
        </button>
      </h2>
      <CollapsibleSection collapsed={collapsed}>
          <div className="space-y-1.5">
            {section.tasks.map((task) => (
              <InteractiveTaskCard
                key={task.id}
                task={task}
                selectionMode={selectionMode}
                selected={selectedIds.has(task.id)}
                bulkBusy={bulkBusy}
                focused={focusedTaskId === task.id}
                hasSelection={selectedIds.size > 0}
                onToggleSelected={onToggleSelected}
                onSelect={(id) => onSelectTask?.(id)}
                onClickWithModifiers={onClickWithModifiers}
              />
            ))}
          </div>
      </CollapsibleSection>
    </section>
  );
}
