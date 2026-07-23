import { memo, type ReactNode } from 'react';
import type { DailyReview } from '@/lib/ipc/tasks/models';
import type { TranslationKey } from '@/lib/i18n';
import { formatCalendarDate } from '@/lib/dates/dateLocale';
import MarkdownContent from '@/components/ui/MarkdownContent';
import { BarrierIcon, CheckIcon, LightbulbIcon, SparkleIcon } from '@/components/ui/icons';
import { Tooltip } from '@/components/ui/Tooltip';
import {
  formatDailyReviewScaleTooltipLabel,
  getDailyReviewScaleOption,
} from '../controller/scaleMetadata.logic';

/**
 * Long-form typography branching (POL-4492 item 3).
 *
 * Uniform `leading-relaxed` (line-height 1.5) on a 400-word reflection
 * paragraph reads as a wall. Two thresholds bump the typography stack:
 *
 *   - `> 200 chars`: switch to a relaxed line-height (~1.7) and add
 *      paragraph spacing so consecutive prose blocks breathe.
 *   - `> 100 words`: apply a serif drop-cap on the very first letter so
 *      a long-form entry visually announces itself as essay-shaped, not
 *      summary-shaped.
 *
 * Word count uses a whitespace split — good enough for the threshold
 * and a no-op for CJK locales where every char counts as one "word"
 * after `split(/\s+/)`; the 200-char path still triggers on those.
 */
const LONG_FORM_CHAR_THRESHOLD = 200;
const DROP_CAP_WORD_THRESHOLD = 100;

function classifyReflectionLength(content: string): {
  longForm: boolean;
  dropCap: boolean;
} {
  const trimmed = content.trim();
  const longForm = trimmed.length > LONG_FORM_CHAR_THRESHOLD;
  if (!longForm) return { longForm, dropCap: false };
  const wordCount = trimmed.split(/\s+/).filter(Boolean).length;
  return { longForm, dropCap: wordCount > DROP_CAP_WORD_THRESHOLD };
}

// Summary is rendered without the icon/label scaffolding the other
// reflection fields use, but it shares the long-form typography stack
// so a 400-word reflection summary doesn't collapse into the same
// uniform 1.5 leading as a 30-word one.
function SummaryBlock({ content }: { content: string }) {
  const { longForm, dropCap } = classifyReflectionLength(content);
  const className = longForm
    ? `text-text-secondary text-sm reflection-longform${
        dropCap ? ' reflection-dropcap' : ''
      }`
    : 'text-text-secondary text-sm leading-relaxed';
  return (
    <div className={className}>
      <MarkdownContent content={content} />
    </div>
  );
}

function ReviewField({ icon, label, content }: { icon: ReactNode; label: string; content: string }) {
  const { longForm, dropCap } = classifyReflectionLength(content);
  // Compose typography classes statically so Tailwind's JIT picks them
  // up. `prose-longform` is a project-local utility defined in
  // index.css that bumps line-height and paragraph margins; the
  // drop-cap is delivered via a `first-letter:` variant on the same
  // wrapper so it scopes to the very first character of the first
  // paragraph.
  const className = longForm
    ? `text-text-secondary text-sm reflection-longform${
        dropCap ? ' reflection-dropcap' : ''
      }`
    : 'text-text-secondary text-xs leading-relaxed';
  return (
    <div>
      <p className="text-text-muted text-xs font-medium mb-1 flex items-center gap-1">
        <span className="inline-flex w-3.5 h-3.5 shrink-0">{icon}</span> {label}
      </p>
      <div className={className}>
        <MarkdownContent content={content} />
      </div>
    </div>
  );
}

export const ReviewCard = memo(function ReviewCard({
  review, locale, t,
}: {
  review: DailyReview;
  locale: string;
  t: (k: TranslationKey) => string;
}) {
  // `formatCalendarDate` anchors the parse at UTC midnight + formats with
  // `timeZone: 'UTC'` so the ymd stays on the intended calendar day
  // regardless of host OS timezone vs app-configured timezone.
  const formattedDate = formatCalendarDate(review.date, locale, {
    weekday: 'long', year: 'numeric', month: 'long', day: 'numeric',
  });
  const moodScale = getDailyReviewScaleOption('mood', review.mood);
  const moodTooltip = formatDailyReviewScaleTooltipLabel({
    kind: 'mood',
    value: review.mood,
    locale,
    t,
  });
  const energyScale = getDailyReviewScaleOption('energy', review.energy_level);
  const energyTooltip = formatDailyReviewScaleTooltipLabel({
    kind: 'energy',
    value: review.energy_level,
    locale,
    t,
  });

  return (
    <article className="bg-surface-2 border border-surface-3 rounded-r-card overflow-hidden">
      <div className="px-5 py-4 flex items-center justify-between border-b border-surface-3">
        <h2 className="heading-section">{formattedDate}</h2>
        <div className="flex items-center gap-3 text-sm">
          {moodScale && moodTooltip && (
            <Tooltip label={moodTooltip}>
              <span>
                {moodScale.icon}
              </span>
            </Tooltip>
          )}
          {energyScale && energyTooltip && (
            <Tooltip label={energyTooltip}>
              <span>
                {energyScale.icon}
              </span>
            </Tooltip>
          )}
        </div>
      </div>

      <div className="px-5 py-4">
        <SummaryBlock content={review.summary} />
      </div>

      <div className="px-5 pb-4 space-y-3">
        {review.wins && <ReviewField icon={<CheckIcon className="w-3.5 h-3.5 text-success" />} label={t('dailyReview.wins')} content={review.wins} />}
        {review.blockers && <ReviewField icon={<BarrierIcon className="w-3.5 h-3.5 text-warning" />} label={t('dailyReview.blockers')} content={review.blockers} />}
        {review.learnings && <ReviewField icon={<LightbulbIcon className="w-3.5 h-3.5 text-accent" />} label={t('dailyReview.learnings')} content={review.learnings} />}
      </div>

      {review.ai_synthesis && (
        <div className="px-5 pb-4 pt-1 border-t border-surface-3 mt-2">
          <p className="text-text-muted text-xs font-medium mb-1.5 flex items-center gap-1">
            <SparkleIcon className="w-3 h-3 text-accent/70" />{t('dailyReview.synthesis')}
          </p>
          <div className="text-text-muted text-xs leading-relaxed italic">
            <MarkdownContent content={review.ai_synthesis ?? ''} />
          </div>
        </div>
      )}
    </article>
  );
})
