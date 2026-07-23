import { useCallback } from 'react';

import type { View } from '../lib/types';
import { formatNumber } from '../locales';
import { useMcpServerStatus } from '../lib/hooks/useMcpServerStatus';
import { useCopyToClipboard } from '../lib/platform/useCopyToClipboard';
import { formatDailyReviewStreakCountLabel } from '../lib/dates/i18nCountPhrases';
import AssistantNotConfiguredPanel from './ui/AssistantNotConfiguredPanel';
import ModuleStatePanel from './ui/ModuleStatePanel';
import { Tooltip } from './ui/Tooltip';
import { Button } from './ui/Button';
import { NotebookIcon, WarningIcon, FlameIcon } from './ui/icons';
import { ReviewCard } from './daily-review/content/ReviewCard';
import { DailyReviewSkeleton } from './daily-review/DailyReviewSkeleton';
import { DaySummarySection } from './daily-review/content/DaySummarySection';
import { MoodEnergySection } from './daily-review/content/MoodEnergySection';
import { ReflectionSection } from './daily-review/content/ReflectionSection';
import { SaveStreakSection } from './daily-review/content/SaveStreakSection';
import { useDailyReviewController } from './daily-review/controller/useDailyReviewController';

interface DailyReviewViewProps {
  /**
   * forwarded from MainViewContent so the empty-state
   * "Connect your AI assistant" card can deep-link into Settings →
   * Assistant MCP when the MCP server status resolves to false.
   */
  onNavigate?: ((view: View) => void) | undefined;
}

export default function DailyReviewView({ onNavigate }: DailyReviewViewProps = {}) {
  const controller = useDailyReviewController();
  const mcpStatus = useMcpServerStatus();
  const mcpUnconfigured = mcpStatus !== null && mcpStatus.resolved === false;
  const { copy, copying } = useCopyToClipboard();

  const handleCopyAddReviewPrompt = useCallback(() => {
    void copy(
      controller.t('dailyReview.addReviewPromptSnippet'),
      controller.t('dailyReview.addReviewPromptCopied'),
    );
  }, [copy, controller]);

  return (
    <div className="h-full flex flex-col overflow-hidden">
      <title>{`Lorvex \u2014 ${controller.t('nav.daily_review')}`}</title>

      <header className="px-4 sm:px-8 pt-1.5 pb-5 shrink-0">
        <p className="text-text-muted text-xs font-medium mb-1">{controller.t('dailyReview.title')}</p>
        <div className="flex items-baseline justify-between">
          <h2 className="text-text-primary text-2xl font-light">{controller.t('dailyReview.subtitle')}</h2>
          <div className="flex items-center gap-3">
            {controller.showTodayScopedInsights && controller.streak > 0 && (
              <Tooltip label={controller.t('dailyReview.streakTitle')}>
                <span className="text-sm text-warning tabular-nums flex items-center gap-1">
                  <FlameIcon className="w-3.5 h-3.5" />
                  {formatDailyReviewStreakCountLabel(controller.locale, controller.streak, controller.t)}
                </span>
              </Tooltip>
            )}
            <Tooltip label={controller.t('dailyReview.addReviewTooltip')}>
              <Button variant="ghost" size="sm" onClick={handleCopyAddReviewPrompt} disabled={copying}>
                {copying ? controller.t('common.copying') : `+ ${controller.t('dailyReview.addReview')}`}
              </Button>
            </Tooltip>
          </div>
        </div>
      </header>

      <div
        ref={controller.scroll.ref}
        onScroll={controller.scroll.onScroll}
        className="flex-1 overflow-y-auto overscroll-contain px-4 sm:px-8 pb-8 space-y-5"
      >
        {controller.showTodayScopedInsights && <DaySummarySection c={controller} />}
        <MoodEnergySection c={controller} />
        <ReflectionSection c={controller} />
        <SaveStreakSection c={controller} />

        {controller.isLoading ? (
          <DailyReviewSkeleton />
        ) : controller.isError && controller.reviews.length === 0 ? (
          <ModuleStatePanel
            variant="error"
            icon={<WarningIcon className="w-9 h-9" />}
            title={controller.t('common.error')}
            actionLabel={controller.t('error.tryAgain')}
            onAction={() => { void controller.refetch(); }}
          />
        ) : controller.pastReviews.length > 0 ? (
          <section>
            <div className="flex items-center gap-2 mb-4">
              <NotebookIcon className="w-4 h-4 text-text-muted" />
              <h2 className="heading-meta">{controller.t('dailyReview.pastEntries')}</h2>
              <span className="text-text-muted text-xs">{formatNumber(controller.locale, controller.pastReviews.length)}</span>
            </div>
            <div className="space-y-4">
              {controller.pastReviews.map(review => (
                <ReviewCard
                  key={review.date}
                  review={review}
                  locale={controller.locale}
                  t={controller.t}
                />
              ))}
            </div>
          </section>
        ) : !controller.todayReview && controller.showTodayScopedInsights ? (
          mcpUnconfigured ? (
            <AssistantNotConfiguredPanel onNavigate={onNavigate} />
          ) : (
            <ModuleStatePanel
              icon={<NotebookIcon className="w-9 h-9" />}
              title={controller.t('dailyReview.empty')}
              subtitle={controller.t('dailyReview.emptyHint')}
            />
          )
        ) : null}
      </div>
    </div>
  );
}
