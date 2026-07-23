import assert from 'node:assert/strict';
import test from 'node:test';

import { loadLocale, translate, type TranslationKey } from '../../../app/src/locales';
import { buildDependencyHeaderSummary } from '../../../app/src/components/dependency-graph/summary';

function t(locale: string) {
  return (key: TranslationKey) => translate(locale, key);
}

test('dependency graph header summary omits zero-count statuses', async () => {
  await loadLocale('en');
  const summary = buildDependencyHeaderSummary('en', 0, 0, 0, t('en'));

  assert.deepEqual(summary, {
    primaryLabel: '0 tasks with dependencies',
    statuses: [],
  });
});

test('dependency graph header summary uses localized blocked and ready count phrases', async () => {
  await loadLocale('ru');
  const summary = buildDependencyHeaderSummary('ru', 7, 2, 3, t('ru'));

  assert.deepEqual(summary, {
    primaryLabel: '7 задач с зависимостями',
    statuses: [
      { kind: 'blocked', label: '2 заблокированные задачи' },
      { kind: 'ready', label: '3 готовые задачи' },
    ],
  });
});

test('dependency graph header summary falls back through shared count-phrase helpers for soft-parity locales', async () => {
  await loadLocale('fr');
  const summary = buildDependencyHeaderSummary('fr', 1, 0, 5, t('fr'));

  assert.deepEqual(summary, {
    primaryLabel: '1 task with dependencies',
    statuses: [
      { kind: 'ready', label: '5 ready tasks' },
    ],
  });
});
