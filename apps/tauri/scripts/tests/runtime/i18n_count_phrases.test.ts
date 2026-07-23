import assert from 'node:assert/strict';
import test from 'node:test';

import { formatNumber, loadLocale, translate, type TranslationKey } from '../../../app/src/locales';
import {
  formatBulkCompletedMessage,
  formatBulkFocusedMessage,
  formatCalendarDayPanelSummary,
  formatDependencyBlockedTaskCountLabel,
  formatListOpenTaskCountLabel,
  formatNotificationDueSoonTaskCountLabel,
  formatNotificationOverdueTaskCountLabel,
  formatOpenTaskCountLabel,
  formatOverdueTaskCountLabel,
  formatPopoverTasksInPlanCountLabel,
  formatReviewCompletedTaskCountLabel,
  formatReviewTaskCountLabel,
  formatSelectedTaskCountLabel,
  formatTaskCountLabel,
  formatTodayTaskCountLabel,
} from '../../../app/src/lib/dates/i18nCountPhrases';

function t(locale: string) {
  return (key: TranslationKey) => translate(locale, key);
}

test('i18n count phrases: Russian task counts honor one/few/many plural categories', async () => {
  await loadLocale('ru');
  const tr = t('ru');

  assert.equal(formatTaskCountLabel('ru', 1, tr), '1 задача');
  assert.equal(formatTaskCountLabel('ru', 2, tr), '2 задачи');
  assert.equal(formatTaskCountLabel('ru', 5, tr), '5 задач');
});

test('i18n count phrases: Chinese today counts keep classifier placement', async () => {
  await loadLocale('zh');
  const tr = t('zh');

  assert.equal(formatTodayTaskCountLabel('zh', 3, tr), '3 项今日任务');
});

test('i18n count phrases: soft-parity today counts fall back to canonical English plural templates', async () => {
  await loadLocale('fr');
  const tr = t('fr');

  assert.equal(formatTodayTaskCountLabel('fr', 0, tr), '0 tasks today');
  assert.equal(formatTodayTaskCountLabel('fr', 3, tr), '3 tasks today');
});

test('i18n count phrases: Arabic zero and two categories use dedicated localized forms', async () => {
  await loadLocale('ar');
  const tr = t('ar');

  assert.equal(formatTaskCountLabel('ar', 0, tr), `${formatNumber('ar', 0)} مهام`);
  assert.equal(formatTaskCountLabel('ar', 2, tr), 'مهمتان');
});

test('i18n count phrases: locale-specific bulk message fallback avoids English template regression', async () => {
  await loadLocale('pl');
  const tr = t('pl');

  assert.equal(formatBulkCompletedMessage('pl', 5, tr), 'Ukończono 5 zadań');
});

test('i18n count phrases: bulk focus can override word order in touched locales', async () => {
  await loadLocale('ko');
  const tr = t('ko');

  assert.equal(formatBulkFocusedMessage('ko', 3, tr), '집중에 추가됨: 작업 3개');
});

test('i18n count phrases: day panel summary fallback stays localized without template key', async () => {
  await loadLocale('uk');
  const tr = t('uk');

  assert.equal(
    formatCalendarDayPanelSummary('uk', 2, 5, tr),
    '2 події, 5 відкритих задач',
  );
});

test('i18n count phrases: touched locales can override day panel summary punctuation and join order', async () => {
  await loadLocale('ar');
  const tr = t('ar');

  assert.equal(
    formatCalendarDayPanelSummary('ar', 2, 5, tr),
    `حدثان، ${formatOpenTaskCountLabel('ar', 5, tr)}`,
  );
});

test('i18n count phrases: notification due-soon labels use locale-specific noun forms', async () => {
  await loadLocale('ko');
  const tr = t('ko');

  assert.equal(
    formatNotificationDueSoonTaskCountLabel('ko', 4, tr),
    '곧 마감되는 작업 4개',
  );
});

test('i18n count phrases: soft-parity overdue fallbacks prefer noun-bearing locale labels when available', async () => {
  await loadLocale('fr');
  const tr = t('fr');

  assert.equal(formatOverdueTaskCountLabel('fr', 1, tr), '1 overdue task');
  assert.equal(formatNotificationOverdueTaskCountLabel('fr', 1, tr), '1 overdue task');
  assert.equal(formatOverdueTaskCountLabel('fr', 5, tr), '5 tâches en retard');
  assert.equal(formatNotificationOverdueTaskCountLabel('fr', 5, tr), '5 tâches en retard');
});

test('i18n count phrases: list open-count labels use locale-native phrasing', async () => {
  await loadLocale('ja');
  const tr = t('ja');

  assert.equal(formatListOpenTaskCountLabel('ja', 4, tr), '4 件の未完了タスク');
});

test('i18n count phrases: dependency blocked-count labels use localized noun order', async () => {
  await loadLocale('ru');
  const tr = t('ru');

  assert.equal(formatDependencyBlockedTaskCountLabel('ru', 2, tr), '2 заблокированные задачи');
});

test('i18n count phrases: popover plan-count labels use locale-native phrasing', async () => {
  await loadLocale('ko');
  const tr = t('ko');

  assert.equal(formatPopoverTasksInPlanCountLabel('ko', 3, tr), '오늘 계획의 작업 3개');
});

test('i18n count phrases: soft-parity plan-count labels fall back to canonical English plural templates', async () => {
  await loadLocale('de');
  const tr = t('de');

  assert.equal(formatPopoverTasksInPlanCountLabel('de', 0, tr), "0 tasks in today's plan");
  assert.equal(formatPopoverTasksInPlanCountLabel('de', 5, tr), "5 tasks in today's plan");
});

test('i18n count phrases: selected-count labels use localized noun order', async () => {
  await loadLocale('ru');
  const tr = t('ru');

  assert.equal(formatSelectedTaskCountLabel('ru', 2, tr), 'Выбрано 2 задачи');
});

test('i18n count phrases: soft-parity selected-count labels fall back to canonical English plural templates', async () => {
  await loadLocale('fr');
  const tr = t('fr');

  assert.equal(formatSelectedTaskCountLabel('fr', 0, tr), '0 selected');
  assert.equal(formatSelectedTaskCountLabel('fr', 5, tr), '5 selected');
});

test('i18n count phrases: soft-parity list and dependency labels fall back to canonical English plural templates', async () => {
  await loadLocale('fr');
  const tr = t('fr');

  assert.equal(formatListOpenTaskCountLabel('fr', 0, tr), '0 open tasks');
  assert.equal(formatDependencyBlockedTaskCountLabel('fr', 0, tr), '0 blocked tasks');
  assert.equal(formatListOpenTaskCountLabel('fr', 5, tr), '5 open tasks');
  assert.equal(formatDependencyBlockedTaskCountLabel('fr', 5, tr), '5 blocked tasks');
});

test('i18n count phrases: weekly review fallback keeps review-specific noun strings when plural keys are absent', async () => {
  await loadLocale('ms');
  const tr = t('ms');

  assert.equal(formatReviewTaskCountLabel('ms', 1, tr), '1 tugasan');
});

test('i18n count phrases: weekly review completed labels stay localized in touched non-English locales', async () => {
  await loadLocale('ru');
  const tr = t('ru');

  assert.equal(formatReviewCompletedTaskCountLabel('ru', 2, tr), '2 задачи выполнены');
});

test('i18n count phrases: weekly review completed fallback stays localized when no completed-count keys exist', async () => {
  await loadLocale('ms');
  const tr = t('ms');

  assert.equal(formatReviewCompletedTaskCountLabel('ms', 2, tr), 'Selesai · 2 tugasan');
});

test('i18n count phrases: open-task fallback avoids adjective-only calendar labels', async () => {
  await loadLocale('fr');
  const tr = t('fr');

  assert.equal(formatOpenTaskCountLabel('fr', 5, tr), '5 tâches');
});
