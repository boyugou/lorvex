import { memo } from 'react';
import { eventDotColor } from '@/lib/colorUtils';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';
import { eventTypeIcon } from '../eventTypeIcon';
import { useI18n, type TranslationKey } from '@/lib/i18n';
import { formatTimeRange, RECURRENCE_SYMBOL } from '../calendarViewUtils';
import { formatCalendarEventAccessibleLabel } from '../calendarEventAccessibility';
import { Tooltip } from '@/components/ui/Tooltip';
import { RevealButton, revealOpacityStyle } from '@/components/ui/RevealButton';
import { useDayEventRowActions } from './useDayEventRowActions';

// wrapped in `memo` so a drag-over hover or sibling row mount
// in `DayPanel` doesn't re-render every event row.
function DayEventRowInner({
  event,
  t,
  onEdit,
  onInvalidate,
  isPast = false,
  editable = true,
  editButtonRef,
}: {
  event: UnifiedCalendarEvent;
  t: (key: TranslationKey) => string;
  // take a stable parent callback that receives the event so
  // the parent doesn't have to allocate a new closure per row each
  // render — keeps `memo` actually skipping unchanged rows.
  onEdit: (event: UnifiedCalendarEvent) => void;
  onInvalidate: () => void;
  isPast?: boolean;
  editable?: boolean;
  /**
   * Ref callback for the row's primary focusable surface —
   * the edit button on editable events. Non-editable events have no
   * interactive element and are skipped by the parent's j/k roving
   * focus.
   */
  editButtonRef?: ((node: HTMLElement | null) => void) | undefined;
}) {
  const { format } = useI18n();
  const handleEdit = () => {
    onEdit(event);
  };
  const {
    canSkipOccurrence,
    confirming,
    handleCancelDelete,
    handleConfirmDelete,
    handleDeleteClick,
    handleSkipOccurrence,
  } = useDayEventRowActions({
    eventId: event.id,
    isRecurring: Boolean(event.recurrence),
    occurrenceDate: event.start_date,
    onInvalidate,
    t,
  });

  // the outer element was a <button> wrapping inner
  // <button>s for skip/delete/cancel. Nested interactive elements
  // are invalid HTML — Tab order is undefined, SR announces "button,
  // button" ambiguously, and Enter/Space on the confirm buttons can
  // bubble to the wrong handler. Restructure as a flex row with a
  // single main-edit button + sibling action buttons inside a
  // role="group" container.
  const bodyContent = (
    <>
      <div
        className="shrink-0 w-1 h-full min-h-[20px] rounded-full mt-0.5"
        style={{ backgroundColor: eventDotColor(event.color ?? null) }}
      />
      <div className="flex-1 min-w-0">
        <p className={`text-xs truncate ${isPast ? 'text-text-muted line-through' : editable ? 'text-text-primary' : 'text-text-muted'}`}>{eventTypeIcon(event.event_type) || (event.recurrence ? RECURRENCE_SYMBOL : '')}{event.title}</p>
        <p className="text-xs text-text-muted font-mono">{formatTimeRange(event, t('calendar.eventAllDay'))}</p>
        {event.location ? (
          <p className="text-xs text-text-muted truncate">{event.location}</p>
        ) : null}
        {!editable ? (
          <p className="text-xs text-text-muted/60 flex items-center gap-0.5 mt-0.5">
            <svg className="w-2.5 h-2.5" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true"><path d="M8 1a4 4 0 0 0-4 4v2H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h10a1 1 0 0 0 1-1V8a1 1 0 0 0-1-1h-1V5a4 4 0 0 0-4-4Zm2 6H6V5a2 2 0 1 1 4 0v2Z"/></svg>
            {t('calendar.providerEvent')}
          </p>
        ) : null}
      </div>
    </>
  );

  const rowClass = `group flex items-start gap-2 px-3 py-2 rounded-r-control transition-colors w-full text-start ${editable ? 'hover:bg-surface-2' : ''} ${isPast ? 'opacity-40' : ''}`;
  const eventLabel = formatCalendarEventAccessibleLabel(event, { format, t });
  const deleteLabel = `${t('calendar.deleteEvent')}: ${eventLabel}`;
  const skipLabel = `${t('calendar.skipOccurrence')}: ${eventLabel}`;
  const cancelLabel = `${t('common.cancel')}: ${eventLabel}`;
  const destructiveActionLabel = canSkipOccurrence ? skipLabel : deleteLabel;

  if (!editable) {
    // Non-editable rows are purely informational — no interactive
    // element, just a labeled group carrying the same event context as
    // editable event controls.
    return (
      <div className={rowClass} role="group" aria-label={eventLabel}>
        {bodyContent}
      </div>
    );
  }

  return (
    <div className={rowClass}>
      <button
        ref={editButtonRef as ((node: HTMLButtonElement | null) => void) | undefined}
        type="button"
        onClick={handleEdit}
        className="flex items-start gap-2 flex-1 min-w-0 text-start cursor-pointer focus-ring-soft rounded-r-control"
        aria-label={eventLabel}
      >
        {bodyContent}
      </button>
      {confirming ? (
        <div className="shrink-0 flex items-center gap-1.5">
          {canSkipOccurrence ? (
            <button
              type="button"
              onClick={handleSkipOccurrence}
              className="text-xs px-2 py-1 rounded-r-control chip-warning chip-warning-interactive active:scale-[0.97] transition-[color,background-color,transform] focus-ring-soft"
              aria-label={skipLabel}
            >
              {t('calendar.skipOccurrence')}
            </button>
          ) : null}
          <button
            type="button"
            onClick={handleConfirmDelete}
            className="text-xs px-2 py-1 rounded-r-control chip-danger chip-danger-interactive active:scale-[0.97] transition-[color,background-color,transform] focus-ring-soft"
            aria-label={deleteLabel}
          >
            {t('calendar.deleteEvent')}
          </button>
          <button
            type="button"
            onClick={handleCancelDelete}
            className="text-xs px-2 py-1 rounded-r-control bg-surface-3 text-text-muted hover:text-text-primary active:scale-[0.97] transition-[color,background-color,transform] focus-ring-soft"
            aria-label={cancelLabel}
          >
            {t('common.cancel')}
          </button>
        </div>
      ) : (
        <Tooltip label={canSkipOccurrence ? t('calendar.skipOccurrence') : t('calendar.deleteEvent')}>
          <RevealButton
            onClick={handleDeleteClick}
            style={revealOpacityStyle(0.6)}
            className="shrink-0 w-6 h-6 flex items-center justify-center hover:bg-[var(--danger-tint-sm)] text-xs"
            aria-label={destructiveActionLabel}
          >
            <span aria-hidden="true">{canSkipOccurrence ? '⊘' : '×'}</span>
          </RevealButton>
        </Tooltip>
      )}
    </div>
  );
}

export const DayEventRow = memo(DayEventRowInner);
