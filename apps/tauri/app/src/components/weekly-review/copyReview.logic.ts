import { formatNumber } from '@/locales';
import type { WeeklyReview } from '@/lib/ipc/tasks/models';
import type { TranslationKey } from '@/lib/i18n';
import { formatReviewTaskCountLabel } from '@/lib/dates/i18nCountPhrases';

interface BuildWeeklyReviewClipboardTextArgs {
  review: WeeklyReview;
  locale: string;
  t: (key: TranslationKey) => string;
}

function formatSignedNumber(locale: string, value: number): string {
  if (value > 0) return `+${formatNumber(locale, value)}`;
  if (value < 0) return `-${formatNumber(locale, Math.abs(value))}`;
  return formatNumber(locale, value);
}

export function buildWeeklyReviewClipboardText({
  review,
  locale,
  t,
}: BuildWeeklyReviewClipboardTextArgs): string {
  const lines: string[] = [`${t('review.title')}\n`];
  const velocity = review.completed_this_week.length - review.created_this_week;

  lines.push(
    `${t('review.completed')}: ${formatNumber(locale, review.completed_this_week.length)}  |  ${t('review.newTasks')}: ${formatNumber(locale, review.created_this_week)}  |  ${t('review.overdue')}: ${formatNumber(locale, review.overdue_count)}  |  ${t('review.netVelocity')}: ${formatSignedNumber(locale, velocity)}`,
  );
  lines.push('');

  if (review.completed_this_week.length > 0) {
    lines.push(`${t('review.completedThisWeek')}:`);
    for (const task of review.completed_this_week) {
      const dur = task.estimated_minutes ? ` (${task.estimated_minutes}${t('common.min')})` : '';
      lines.push(`  - [x] ${task.title}${dur}`);
    }
    lines.push('');
  }

  if (review.overdue_tasks.length > 0) {
    lines.push(`${t('review.overdue')} (${formatNumber(locale, review.overdue_count)}):`);
    for (const task of review.overdue_tasks) {
      lines.push(`  - [ ] ${task.title}`);
    }
    lines.push('');
  }

  if (review.stalled_lists.length > 0) {
    lines.push(`${t('review.inactiveProjects')}:`);
    for (const stalledList of review.stalled_lists) {
      lines.push(
        `  - ${stalledList.name} (${formatReviewTaskCountLabel(locale, stalledList.open_task_count, t)})`,
      );
    }
    lines.push('');
  }

  if (review.frequently_deferred.length > 0) {
    lines.push(`${t('review.stuckTasks')}:`);
    for (const task of review.frequently_deferred) {
      lines.push(`  - ${task.title} (${formatNumber(locale, task.defer_count ?? 0)}x ${t('review.deferredTimes')})`);
    }
    lines.push('');
  }

  return lines.join('\n').trimEnd();
}
