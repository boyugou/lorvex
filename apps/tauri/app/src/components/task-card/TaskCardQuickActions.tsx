import { useI18n } from '@/lib/i18n';
import type { Task } from '@/lib/ipc/tasks/models';
import { LONG_PRESS_IGNORE_ATTRIBUTE } from '@/lib/useLongPress';
import { Tooltip } from '../ui/Tooltip';
import { useTaskCardQuickActionHandlers } from './useTaskCardQuickActionHandlers';

interface TaskCardQuickActionsProps {
  task: Task;
}

const quickActionButtonClass =
  'inline-flex min-w-6 min-h-6 items-center justify-center p-1 shrink-0 rounded-r-control active:scale-[0.97] transition-colors focus-ring-soft [@media(hover:none)]:min-w-11 [@media(hover:none)]:min-h-11 [@media(hover:none)]:p-3';
const longPressIgnoreProps = { [LONG_PRESS_IGNORE_ATTRIBUTE]: '' };

export function TaskCardQuickActions({ task }: TaskCardQuickActionsProps) {
  const { t } = useI18n();
  const {
    actionPending,
    canPromote,
    isActive,
    handleDeferNextWeek,
    handleDeferTomorrow,
    handlePromote,
  } = useTaskCardQuickActionHandlers(task);

  if (!isActive) return null;

  return (
    <div className="reveal-on-hover cv-inline-slide-1 flex items-center gap-1 duration-200 shrink-0">
      {canPromote && (
        <Tooltip label={t('contextMenu.promoteToActive')}>
          <button
            type="button"
            {...longPressIgnoreProps}
            onClick={(event) => {
              event.stopPropagation();
              void handlePromote();
            }}
            disabled={actionPending}
            className={`${quickActionButtonClass} text-text-muted hover:text-success hover:bg-surface-3`}
            aria-label={t('contextMenu.promoteToActive')}
          >
            <svg width="14" height="14" viewBox="0 0 16 16" fill="none" className="block">
              <path d="M5 3l7 5-7 5V3z" fill="currentColor" />
            </svg>
          </button>
        </Tooltip>
      )}
      <Tooltip label={t('popover.deferTomorrow')}>
        <button
          type="button"
          {...longPressIgnoreProps}
          onClick={(event) => {
            event.stopPropagation();
            void handleDeferTomorrow();
          }}
          disabled={actionPending}
          className={`${quickActionButtonClass} text-text-muted hover:text-accent hover:bg-surface-3`}
          aria-label={t('popover.deferTomorrow')}
        >
          <svg width="14" height="14" viewBox="0 0 16 16" fill="none" className="block">
            <path d="M8 3v5l3.5 2" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
            <circle cx="8" cy="8" r="6.5" stroke="currentColor" strokeWidth="1.5" />
            <path d="M12 12l2 2" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
          </svg>
        </button>
      </Tooltip>
      <Tooltip label={t('task.defer.nextWeek')}>
        <button
          type="button"
          {...longPressIgnoreProps}
          onClick={(event) => {
            event.stopPropagation();
            void handleDeferNextWeek();
          }}
          disabled={actionPending}
          className={`hidden @xs:inline-flex ${quickActionButtonClass} text-text-muted hover:text-warning hover:bg-surface-3`}
          aria-label={t('task.defer.nextWeek')}
        >
          <svg width="14" height="14" viewBox="0 0 16 16" fill="none" className="block">
            <rect x="2" y="3" width="12" height="10" rx="1.5" stroke="currentColor" strokeWidth="1.5" />
            <path d="M2 6h12" stroke="currentColor" strokeWidth="1.5" />
            <path d="M5.5 1.5v3M10.5 1.5v3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
          </svg>
        </button>
      </Tooltip>
    </div>
  );
}
