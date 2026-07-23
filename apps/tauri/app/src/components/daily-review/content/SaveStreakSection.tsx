import { useMemo } from 'react';

import { formatDailyReviewStreakCountLabel } from '@/lib/dates/i18nCountPhrases';
import { formatCalendarDateInTimeZone } from '@/lib/dates/dateLocale';
import type { DailyReviewController } from '../controller/useDailyReviewController';
import { Button } from '@/components/ui/Button';
import { TonalIconBubble } from '@/components/ui/TonalIconBubble';
import { CheckIcon, FlameIcon } from '@/components/ui/icons';

export function SaveStreakSection({ c }: { c: DailyReviewController }) {
  const formattedDate = useMemo(() => {
    return formatCalendarDateInTimeZone(c.displayDateYmd, c.locale, c.timezone, {
      weekday: 'long',
      month: 'long',
      day: 'numeric',
    });
  }, [c.displayDateYmd, c.locale, c.timezone]);

  return (
    <section className="bg-surface-2 rounded-r-card border border-card overflow-hidden">
      <div className="px-5 py-4 flex flex-col sm:flex-row items-center gap-4">
        {c.showTodayScopedInsights && c.streak > 0 && (
          <div className="flex items-center gap-3 shrink-0">
            <TonalIconBubble tone="warning" size="lg" tint="sm">
              <FlameIcon className="w-6 h-6 text-warning" />
            </TonalIconBubble>
            <div>
              <p className="text-text-primary text-lg font-light tabular-nums">
                {formatDailyReviewStreakCountLabel(c.locale, c.streak, c.t)}
              </p>
              <p className="text-text-muted text-2xs">{c.t('dailyReview.reviewStreak')}</p>
            </div>
          </div>
        )}

        <div className="flex-1" />

        <div className="flex items-center gap-3">
          {c.justSaved && (
            <span className="text-success text-xs font-medium animate-[fade-in_0.3s_ease-out] flex items-center gap-1">
              <CheckIcon className="w-3.5 h-3.5" />
              {c.format('dailyReview.savedFor', { date: formattedDate })}
            </span>
          )}
          <Button
            variant="primary"
            size="lg"
            onClick={c.handleSaveClick}
            disabled={c.saving}
            className={c.justSaved ? '!bg-success hover:!bg-success' : ''}
          >
            {c.saving ? c.t('common.saving') : c.justSaved ? (
              <span className="flex items-center gap-1.5">
                <CheckIcon className="w-4 h-4" />
                {c.t('dailyReview.saved')}
              </span>
            ) : c.t('dailyReview.save')}
          </Button>
        </div>
      </div>

      {c.showTodayScopedInsights && c.todayReview && (
        <div className="px-5 pb-3 flex justify-end">
          <button
            type="button"
            onClick={() => { void c.handleCopyTodayEntry(); }}
            disabled={c.copying}
            className="text-text-muted text-2xs hover:text-text-secondary transition-colors disabled:opacity-50 focus-ring-soft rounded-r-control"
          >
            {c.copying ? c.t('common.copying') : c.t('dailyReview.copyEntry')}
          </button>
        </div>
      )}
    </section>
  );
}
