import { useI18n } from '@/lib/i18n';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { formatRelativeTime, formatTimestamp } from '@/lib/dates/dateLocale';
import MarkdownContent from '@/components/ui/MarkdownContent';
import { SectionLabel, DetailSectionGroup } from '../TaskDetailPrimitives';
import { formatAttributionActor, type TaskDetailControllerState } from '../support';
import { TASK_STATUS } from '@lorvex/shared/types';

/** AI notes — rendered in the "Advanced" section, always visible when present. */
export function TaskDetailAiNotes({
  controller,
}: {
  controller: Pick<TaskDetailControllerState, 't'> & {
    task: NonNullable<TaskDetailControllerState['task']>;
  };
}) {
  const { t, task } = controller;
  if (!task.ai_notes) return null;

  return (
    <section aria-label={t('task.aiNotesAriaLabel')}>
      <SectionLabel>
        &#10022; {t('task.aiNotes')}
        <span
          className="ms-2 text-2xs font-normal text-text-tertiary"
          title={t('task.aiNotesReadOnlyHint')}
        >
          {t('task.aiNotesReadOnlyBadge')}
        </span>
      </SectionLabel>
      <div
        className="bg-accent/5 border border-accent/10 rounded-r-control p-3 text-sm text-text-secondary leading-relaxed select-text-content"
        aria-readonly="true"
      >
        <MarkdownContent content={task.ai_notes ?? ''} />
      </div>
    </section>
  );
}

/** Debug / provenance info — collapsed by default, contains raw input, timestamps, attribution. */
export function TaskDetailDebugInfo({
  controller,
}: {
  controller: Pick<TaskDetailControllerState, 'attribution' | 't'> & {
    task: NonNullable<TaskDetailControllerState['task']>;
  };
}) {
  const { attribution, t, task } = controller;
  const { locale, format } = useI18n();
  const { timezone } = useConfiguredDayContext();

  const hasRawInput = !!task.raw_input;
  const hasAnyInfo = hasRawInput || task.created_at;

  if (!hasAnyInfo) return null;

  return (
    <DetailSectionGroup title={t('taskDetail.section.info')} defaultExpanded={false}>
      <div className="space-y-2.5">
        {hasRawInput && (
          <div>
            <span className="text-2xs text-text-muted/60 font-medium">{t('task.originalInput')}</span>
            <p className="text-2xs text-text-muted/70 italic mt-0.5 select-text-content leading-relaxed">"{task.raw_input}"</p>
          </div>
        )}

        <div className="grid grid-cols-2 gap-x-4 gap-y-1 text-2xs text-text-muted/60">
          <span>{t('task.created')}</span>
          <span className="text-text-muted/80">{formatTimestamp(task.created_at, locale, timezone)} ({formatRelativeTime(task.created_at, locale, t, format, timezone)})</span>

          <span>{t('task.createdBy')}</span>
          <span className="text-text-muted/80">{formatAttributionActor(attribution?.created_by, t)}</span>

          <span>{t('task.updated')}</span>
          <span className="text-text-muted/80">{formatTimestamp(task.updated_at, locale, timezone)} ({formatRelativeTime(task.updated_at, locale, t, format, timezone)})</span>

          <span>{t('task.lastModifiedBy')}</span>
          <span className="text-text-muted/80">{formatAttributionActor(attribution?.last_modified_by, t)}</span>

          {task.completed_at && (
            <>
              <span>{t('task.completedAt')}</span>
              <span className="text-text-muted/80">{formatTimestamp(task.completed_at, locale, timezone)}</span>
            </>
          )}

          {task.last_deferred_at && (
            <>
              <span>{t('task.deferred')}</span>
              <span className="text-text-muted/80">{formatTimestamp(task.last_deferred_at, locale, timezone)}</span>
            </>
          )}

          {task.status === TASK_STATUS.cancelled && (
            <>
              <span>{t('task.deletedBy')}</span>
              <span className="text-text-muted/80">{formatAttributionActor(attribution?.deleted_by, t)}</span>
            </>
          )}
        </div>
      </div>
    </DetailSectionGroup>
  );
}
