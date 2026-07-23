import {
  formatDependencyBlockedTaskCountLabel,
  formatDependencyReadyTaskCountLabel,
  formatDependencyTasksWithDepsCountLabel,
} from '@/lib/dates/i18nCountPhrases';
import type { TranslationKey } from '@/lib/i18n';

type Translator = (key: TranslationKey) => string;

interface DependencyHeaderStatusLabel {
  kind: 'blocked' | 'ready';
  label: string;
}

interface DependencyHeaderSummary {
  primaryLabel: string;
  statuses: DependencyHeaderStatusLabel[];
}

/**
 * Build the dependency-view header copy.
 *
 * Three label shapes the header has to express:
 *   - No filter active → "{n} tasks with dependencies" + blocked/ready
 *     pill statuses.
 *   - Filter active and *some* clusters match → same shape; the totals
 *     reflect the full population, the body lists the filtered subset.
 *   - Filter active and *no* clusters match → "No matching tasks"
 *     primary label, no status pills. The body renders its own
 *     no-match panel; the header must not read "0 tasks with
 *     dependencies" while real deps exist off-screen.
 *
 * The `filteredToEmpty` flag selects the third shape; callers compute
 * it as `isFilterActive && filteredClusters.length === 0 &&
 * totalDepsExist` (deps exist in the dataset, the filter just zeroed
 * the visible set).
 */
export function buildDependencyHeaderSummary(
  locale: string,
  totalWithDeps: number,
  totalBlocked: number,
  totalReady: number,
  t: Translator,
  filteredToEmpty: boolean = false,
): DependencyHeaderSummary {
  if (filteredToEmpty) {
    return {
      primaryLabel: t('deps.noMatchingTasks'),
      statuses: [],
    };
  }

  const statuses: DependencyHeaderStatusLabel[] = [];

  if (totalBlocked > 0) {
    statuses.push({
      kind: 'blocked',
      label: formatDependencyBlockedTaskCountLabel(locale, totalBlocked, t),
    });
  }

  if (totalReady > 0) {
    statuses.push({
      kind: 'ready',
      label: formatDependencyReadyTaskCountLabel(locale, totalReady, t),
    });
  }

  return {
    primaryLabel: formatDependencyTasksWithDepsCountLabel(locale, totalWithDeps, t),
    statuses,
  };
}
