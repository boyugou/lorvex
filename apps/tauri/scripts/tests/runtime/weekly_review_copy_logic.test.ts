import assert from 'node:assert/strict';
import test from 'node:test';

import { buildWeeklyReviewClipboardText } from '../../../app/src/components/weekly-review/copyReview.logic';
import { translate } from '../../../app/src/locales';
import type { TranslationKey } from '../../../app/src/lib/i18n';
import type { WeeklyReview } from '../../../app/src/lib/ipc';

const t = (key: TranslationKey) => translate('en', key);

function makeReview(overrides: Partial<WeeklyReview> = {}): WeeklyReview {
  return {
    completed_this_week: [],
    stalled_lists: [],
    frequently_deferred: [],
    overdue_count: 0,
    overdue_tasks: [],
    someday_items: [],
    created_this_week: 0,
    completed_with_estimate_count: 0,
    estimate_coverage_ratio: null,
    estimate_accuracy_sample_count: 0,
    estimate_mean_absolute_pct_error: null,
    ...overrides,
  };
}

test('weekly review clipboard summary preserves a minus sign for negative net velocity', () => {
  const text = buildWeeklyReviewClipboardText({
    review: makeReview({
      completed_this_week: [
        {
          id: 'task-a',
          title: 'Task A',
          status: 'completed',
        } as WeeklyReview['completed_this_week'][number],
      ],
      created_this_week: 4,
      overdue_count: 2,
    }),
    locale: 'en',
    t,
  });

  assert.match(text, /Net: -3/);
});

test('weekly review clipboard summary localizes numeric counts', () => {
  const text = buildWeeklyReviewClipboardText({
    review: makeReview({
      created_this_week: 12,
      overdue_count: 7,
      frequently_deferred: [
        {
          id: 'task-b',
          title: 'Task B',
          status: 'open',
          defer_count: 1234,
        } as WeeklyReview['frequently_deferred'][number],
      ],
    }),
    locale: 'ar-EG',
    t: (key) => translate('ar', key),
  });

  assert.match(text, /١٢/);
  assert.match(text, /٧/);
  assert.match(text, /١٬٢٣٤x/);
});
