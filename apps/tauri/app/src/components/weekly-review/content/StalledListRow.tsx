import type { StalledList } from '@/lib/ipc/tasks/models';
import { type TranslationKey } from '@/lib/i18n';
import { formatReviewTaskCountLabel } from '@/lib/dates/i18nCountPhrases';
import { formatTimestamp } from '@/lib/dates/dateLocale';
import { formatNumber } from '@/locales';
import { Button } from '@/components/ui/Button';
import { DAY_MS } from '@/lib/time/durations';

interface StalledListRowProps {
  stalledList: StalledList;
  t: (key: TranslationKey) => string;
  locale: string;
  archiving: boolean;
  onOpenList?: ((listId: string) => void) | undefined;
  onArchive: () => void;
}

export default function StalledListRow({
  stalledList,
  t,
  locale,
  archiving,
  onOpenList,
  onArchive,
}: StalledListRowProps) {
  const daysAgo = Math.floor((Date.now() - new Date(stalledList.last_activity).getTime()) / DAY_MS);
  // `last_activity` is an ISO timestamp, not a YYYY-MM-DD calendar date, so
  // `formatCalendarDate` (which anchors to UTC midnight) would shift the
  // date for users west of UTC late in the day. Use `formatTimestamp` with
  // date-only options instead — falls through to the user's local OS tz.
  const lastActivityDate = formatTimestamp(
    stalledList.last_activity,
    locale,
    undefined,
    { month: 'short', day: 'numeric' },
  );

  return (
    <div className="bg-surface-2 border border-card rounded-r-card px-4 py-3.5">
      <div className="flex items-center gap-3">
        <span className="text-base shrink-0">{stalledList.icon ?? '\uD83D\uDCCB'}</span>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <span className="text-sm text-text-primary font-medium truncate">{stalledList.name}</span>
            <span className="text-2xs text-text-muted tabular-nums shrink-0">
              {formatReviewTaskCountLabel(locale, stalledList.open_task_count, t)}
            </span>
          </div>
          <div className="text-xs text-text-muted/70 mt-0.5">
            {t('review.lastActivity')}: {lastActivityDate} ({formatNumber(locale, daysAgo)}{t('time.daysAgo')})
          </div>
        </div>
      </div>
      <div className="mt-2.5 flex items-center gap-2 ps-8">
        <Button
          variant="outline"
          size="xs"
          onClick={() => onOpenList?.(stalledList.id)}
          className="active:scale-[0.97]"
        >
          {t('review.openList')}
        </Button>
        <button
          type="button"
          onClick={onArchive}
          disabled={archiving}
          className="text-2xs px-2.5 py-1.5 rounded-r-control chip-warning chip-warning-interactive active:scale-[0.97] transition-[color,background-color,transform] disabled:opacity-50 disabled:cursor-not-allowed focus-ring-soft"
        >
          {archiving ? t('review.archiving') : t('review.shelveToSomeday')}
        </button>
      </div>
    </div>
  );
}
