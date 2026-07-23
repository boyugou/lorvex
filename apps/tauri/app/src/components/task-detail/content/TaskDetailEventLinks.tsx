import { useMemo } from 'react';

import type { TranslationKey } from '@/lib/i18n';
import { formatTimeRange } from '@/components/calendar/calendarViewUtils';
import { Tooltip } from '@/components/ui/Tooltip';
import { RevealButton } from '@/components/ui/RevealButton';
import { SectionLabel } from '../TaskDetailPrimitives';
import { TaskDetailEventLinkSearchInput } from './TaskDetailEventLinkSearchInput';
import { useTaskDetailEventLinkActions } from './useTaskDetailEventLinkActions';
import { useTaskDetailEventLinkComposer } from './useTaskDetailEventLinkComposer';
import { useTaskDetailEventLinkQueries } from './useTaskDetailEventLinkQueries';
import { buildTaskDetailProviderEventUnifiedId } from './useTaskDetailEventLinkSearch';

interface TaskDetailEventLinksProps {
  taskId: string;
  t: (key: TranslationKey) => string;
}

function providerLinkBadge(resolutionState: string): { key: TranslationKey; className: string } {
  switch (resolutionState) {
    case 'missing':
      return { key: 'task.providerLinkMissing', className: 'bg-[var(--warning-tint-md)] text-warning' };
    case 'pending':
      return { key: 'task.providerLinkPending', className: 'bg-accent/10 text-accent' };
    case 'stale':
      return { key: 'task.providerLinkStale', className: 'bg-[var(--warning-tint-md)] text-warning' };
    default:
      return { key: 'task.providerLinkUnavailable', className: 'bg-surface-3 text-text-muted' };
  }
}

export function TaskDetailEventLinks({ taskId, t }: TaskDetailEventLinksProps) {
  const { eventIds, eventMap, links, providerLinks } = useTaskDetailEventLinkQueries(taskId);
  const excludedEventIds = useMemo(
    () => [
      ...eventIds,
      ...providerLinks.map(buildTaskDetailProviderEventUnifiedId),
    ],
    [eventIds, providerLinks],
  );
  const {
    linkCanonicalEvent,
    linkProviderEvent,
    unlinkCanonicalEvent,
    unlinkProviderEvent,
  } = useTaskDetailEventLinkActions(taskId);
  const {
    adding,
    cancelAdding,
    handleSelectEvent,
    toggleAdding,
  } = useTaskDetailEventLinkComposer({
    onLinkCanonicalEvent: linkCanonicalEvent,
    onLinkProviderEvent: linkProviderEvent,
  });

  return (
    <>
      <section className="space-y-2">
        <SectionLabel>{t('task.linkedEvents')}</SectionLabel>

        {links.length > 0 ? (
          <div className="space-y-1">
            {links.map((link) => {
              const ev = eventMap[link.calendar_event_id];
              return (
                <div key={link.calendar_event_id} className="group flex items-center gap-2">
                  <div
                    className="shrink-0 w-1 h-4 rounded-full"
                    style={{ backgroundColor: ev?.color || 'var(--color-warning)' }}
                  />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm text-text-secondary truncate">
                      {ev?.title ?? link.calendar_event_id.slice(0, 8) + '...'}
                    </p>
                    <p className="text-xs text-text-muted">
                      {ev ? `${ev.start_date} ${formatTimeRange(ev, t('calendar.eventAllDay'))}` : ''}
                    </p>
                  </div>
                  <Tooltip label={t('task.unlinkEvent')}>
                    <RevealButton
                      onClick={() => unlinkCanonicalEvent(link.calendar_event_id)}
                      className="text-xs px-1"
                      aria-label={t('task.unlinkEvent')}
                    >
                      {/* hide the ×-glyph from AT so
                          SR users hear the real `aria-label` (Unlink
                          event) rather than "multiplication sign". */}
                      <span aria-hidden="true">×</span>
                    </RevealButton>
                  </Tooltip>
                </div>
              );
            })}
          </div>
        ) : null}

        <button
          type="button"
          onClick={toggleAdding}
          className="text-xs text-text-muted hover:text-accent transition-colors rounded-r-control focus-ring-soft"
        >
          + {t('task.linkToEvent')}
        </button>

        {adding && (
          <TaskDetailEventLinkSearchInput
            t={t}
            excludeIds={excludedEventIds}
            onSelect={handleSelectEvent}
            onCancel={cancelAdding}
          />
        )}
      </section>

      {providerLinks.length > 0 && (
        <section className="space-y-2">
          <SectionLabel>{t('task.providerLinks')}</SectionLabel>
          <div className="space-y-1">
            {providerLinks.map((link) => {
              const linkKey = buildTaskDetailProviderEventUnifiedId(link);
              const resolved = link.resolution_state === 'resolved';
              const badge = providerLinkBadge(link.resolution_state);
              return (
                <div key={linkKey} className="group flex items-center gap-2">
                  <div
                    className="shrink-0 w-1 h-4 rounded-full"
                    style={{ backgroundColor: resolved ? 'var(--color-accent)' : 'var(--color-text-muted)' }}
                  />
                  <div className="flex-1 min-w-0">
                    {resolved ? (
                      <>
                        <p className="text-sm text-text-secondary truncate">
                          {link.event_title}
                        </p>
                        <p className="text-xs text-text-muted">
                          {link.event_start_date}
                          {link.event_start_time ? ` ${link.event_start_time}` : ''}
                          <span className="ms-1.5 text-text-muted/60">{link.provider_kind}</span>
                        </p>
                      </>
                    ) : (
                      <>
                        <p className="text-sm text-text-muted truncate italic">
                          {link.provider_event_key.slice(0, 16)}...
                        </p>
                        <p className="text-xs text-text-muted">
                          <span className={`inline-flex items-center px-1 py-px rounded-r-control text-3xs font-medium ${badge.className}`}>
                            {t(badge.key)}
                          </span>
                          <span className="ms-1.5 text-text-muted/60">{link.provider_kind}</span>
                        </p>
                      </>
                    )}
                  </div>
                  <Tooltip label={t('task.unlinkProviderEvent')}>
                    <RevealButton
                      onClick={() => unlinkProviderEvent(link)}
                      className="text-xs px-1"
                      aria-label={t('task.unlinkProviderEvent')}
                    >
                      <span aria-hidden="true">×</span>
                    </RevealButton>
                  </Tooltip>
                </div>
              );
            })}
          </div>
        </section>
      )}
    </>
  );
}
