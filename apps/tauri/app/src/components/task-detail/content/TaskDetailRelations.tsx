import { useState } from 'react';
import { useI18n } from '@/lib/i18n';
import { Tooltip } from '@/components/ui/Tooltip';
import { RevealButton } from '@/components/ui/RevealButton';
import { DepLink, SectionLabel } from '../TaskDetailPrimitives';
import type { TaskDetailControllerState } from '../support';
import { TaskDetailRelationSearchInput } from './TaskDetailRelationSearchInput';
import { useTaskDetailRelationActions } from './useTaskDetailRelationActions';
import { useTaskDetailRelationComposer } from './useTaskDetailRelationComposer';
import { wouldCreateCycle as wouldCreateCycleAgainstSnapshot } from './relationCyclePrecheck';

type RelationsController = Pick<
  TaskDetailControllerState,
  'blocksIds' | 'dependsOnIds' | 'depTaskMap' | 'onSelectTask' | 't' | 'task'
>;

/**
 * Rows to render before collapsing the rest behind a "Show all" toggle.
 * With 5 rows visible the detail panel keeps a predictable height even for
 * tasks with many blockers or blockees; the rest are opt-in via the toggle.
 */
const INITIAL_SHOW = 5;

export function TaskDetailRelations({
  controller,
}: {
  controller: RelationsController;
}) {
  const { blocksIds, dependsOnIds, depTaskMap, onSelectTask, t, task } = controller;
  const { format } = useI18n();
  const {
    handleAddBlocks,
    handleAddDependsOn,
    handleRemoveBlocks,
    handleRemoveDependsOn,
  } = useTaskDetailRelationActions({
    taskId: task?.id ?? null,
  });

  const {
    addingType,
    cancelAdding,
    excludeIds,
    graphSnapshot,
    handleSelectTask,
    startAddingBlocks,
    startAddingDependsOn,
  } = useTaskDetailRelationComposer({
    taskId: task?.id ?? null,
    blocksIds,
    dependsOnIds,
    onAddBlocks: handleAddBlocks,
    onAddDependsOn: handleAddDependsOn,
  });

  const [blockersExpanded, setBlockersExpanded] = useState(false);
  const [blocksExpanded, setBlocksExpanded] = useState(false);

  const blockersOverflow = dependsOnIds.length > INITIAL_SHOW;
  const blocksOverflow = blocksIds.length > INITIAL_SHOW;
  const visibleDependsOnIds =
    blockersOverflow && !blockersExpanded
      ? dependsOnIds.slice(0, INITIAL_SHOW)
      : dependsOnIds;
  const visibleBlocksIds =
    blocksOverflow && !blocksExpanded ? blocksIds.slice(0, INITIAL_SHOW) : blocksIds;

  const toggleButtonClass =
    'text-xs text-text-muted hover:text-accent transition-colors rounded-r-control focus-ring-soft';

  return (
    <section className="space-y-2">
      <SectionLabel>{t('task.dependencies')}</SectionLabel>

      {dependsOnIds.length > 0 && (
        <div>
          <p className="text-text-muted text-xs font-medium mb-1">{t('task.blockedBy')}</p>
          <div className="space-y-1">
            {visibleDependsOnIds.map((id) => {
              const dep = depTaskMap[id];
              return (
                <div key={id} className="group flex items-center gap-1">
                  <div className="flex-1 min-w-0">
                    <DepLink
                      id={id}
                      title={dep?.title}
                      status={dep?.status}
                      onSelect={onSelectTask}
                    />
                  </div>
                  <Tooltip label={t('common.remove')}>
                    <RevealButton
                      onClick={() => { void handleRemoveDependsOn(id); }}
                      className="text-xs px-1"
                      aria-label={t('common.remove')}
                    >
                      {/* hide the ×-glyph from AT so
                          SR users hear the real `aria-label` (Remove
                          dependency) instead of "multiplication sign". */}
                      <span aria-hidden="true">×</span>
                    </RevealButton>
                  </Tooltip>
                </div>
              );
            })}
          </div>
          {blockersOverflow && (
            <button
              type="button"
              onClick={() => setBlockersExpanded((prev) => !prev)}
              className={`${toggleButtonClass} mt-1`}
              aria-expanded={blockersExpanded}
            >
              {blockersExpanded
                ? t('taskDetail.relations.collapseBlockers')
                : format('taskDetail.relations.showAllBlockers', { count: dependsOnIds.length })}
            </button>
          )}
        </div>
      )}

      {blocksIds.length > 0 && (
        <div>
          <p className="text-text-muted text-xs font-medium mb-1">{t('task.blocks')}</p>
          <div className="space-y-1">
            {visibleBlocksIds.map((id) => {
              const dep = depTaskMap[id];
              return (
                <div key={id} className="group flex items-center gap-1">
                  <div className="flex-1 min-w-0">
                    <DepLink
                      id={id}
                      title={dep?.title}
                      status={dep?.status}
                      onSelect={onSelectTask}
                    />
                  </div>
                  <Tooltip label={t('common.remove')}>
                    <RevealButton
                      onClick={() => { void handleRemoveBlocks(id); }}
                      className="text-xs px-1"
                      aria-label={t('common.remove')}
                    >
                      {/* hide the ×-glyph from AT so
                          SR users hear the real `aria-label` (Remove
                          dependency) instead of "multiplication sign". */}
                      <span aria-hidden="true">×</span>
                    </RevealButton>
                  </Tooltip>
                </div>
              );
            })}
          </div>
          {blocksOverflow && (
            <button
              type="button"
              onClick={() => setBlocksExpanded((prev) => !prev)}
              className={`${toggleButtonClass} mt-1`}
              aria-expanded={blocksExpanded}
            >
              {blocksExpanded
                ? t('taskDetail.relations.collapseBlocks')
                : format('taskDetail.relations.showAllBlocks', { count: blocksIds.length })}
            </button>
          )}
        </div>
      )}

      <div className="flex items-center gap-2 flex-wrap">
        <button
          type="button"
          onClick={startAddingDependsOn}
          className="text-xs text-text-muted hover:text-accent transition-colors rounded-r-control focus-ring-soft"
        >
          + {t('task.addDependency')}
        </button>
        <button
          type="button"
          onClick={startAddingBlocks}
          className="text-xs text-text-muted hover:text-accent transition-colors rounded-r-control focus-ring-soft"
        >
          + {t('task.addBlocking')}
        </button>
      </div>

      {addingType && (
        <TaskDetailRelationSearchInput
          placeholder={t('task.searchTasks')}
          noResultsLabel={t('common.noResults')}
          excludeIds={excludeIds}
          onSelect={handleSelectTask}
          onCancel={cancelAdding}
          wouldCreateCycle={
            graphSnapshot
              ? (candidateId) => wouldCreateCycleAgainstSnapshot(graphSnapshot, addingType, candidateId)
              : null
          }
          cycleBadgeLabel={t('taskDetail.relations.wouldCreateCycle')}
          cycleHintLabel={t('taskDetail.relations.wouldCreateCycleHint')}
        />
      )}
    </section>
  );
}
