import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const repoRoot = process.cwd();

function readSource(relativePath: string): string {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

const PARAMETERIZED_TOAST_KEYS = [
  'capture.taskCreateSuccessWithTitle',
  'listPicker.moveSuccess',
  'palette.cycleThemeChanged',
  'palette.importDataResult',
  'palette.permanentDeleteTaskDone',
  'palette.purgeCancelledResult',
  'palette.resetSyncResult',
  'settings.dangerClearChangelogDoneCount',
  'settings.exportSavedToPath',
  'settings.languageChanged',
  'settings.nativeCalendarClearedCount',
  'settings.nativeCalendarSyncedSummary',
  'settings.purgeCancelledResult',
  'review.deferArchivedNamed',
  'review.deferRescopedNamed',
  'review.deferScheduledNamed',
  'review.shelvedToSomedayNamed',
  'review.taskCancelledNamed',
  'review.taskCompletedNamed',
  'task.deferredNamed',
  'task.duplicatedNamed',
  'task.status.cancelledNamed',
  'task.status.completedNamed',
] as const;

test('parameterized toast sentence keys exist in every strict-parity catalog', () => {
  const strictLocales = JSON.parse(readSource('app/src/locales/strict-parity.json')) as string[];

  for (const locale of strictLocales) {
    const catalog = JSON.parse(readSource(`app/src/locales/${locale}.json`)) as Record<string, string>;
    for (const key of PARAMETERIZED_TOAST_KEYS) {
      assert.equal(typeof catalog[key], 'string', `${locale}.json should define ${key}`);
      assert.match(catalog[key], /\{[^}]+\}/, `${locale}.json ${key} should keep variables in the locale sentence`);
    }
  }
});

test('reported toast surfaces use parameterized locale sentences instead of translated fragments', () => {
  const listPicker = readSource('app/src/components/ui/ListPickerOverlay.tsx');
  const quickCapture = readSource('app/src/components/quick-capture/useQuickCaptureSubmit.ts');
  const weeklyReview = readSource('app/src/components/weekly-review/useWeeklyReviewController.ts');
  const systemActions = readSource('app/src/components/command-palette/controller/systemActions.ts');
  const paletteMutations = readSource('app/src/components/command-palette/controller/mutations.ts');
  const dangerZone = readSource('app/src/components/settings/data/useDangerZoneActions.ts');
  const nativeCalendar = readSource('app/src/components/settings/calendar/useNativeCalendarPanelController.logic.ts');
  const taskDetailLifecycle = readSource('app/src/components/task-detail/controller/mutations/lifecycle.ts');
  const swipeActions = readSource('app/src/components/task-card/useSwipeableTaskCardActions.ts');
  const taskListActions = readSource('app/src/lib/tasks/taskActions/lifecycle.ts');
  const snapshotActions = readSource('app/src/components/settings/controller/data/snapshot/actions/payload.ts');

  assert.match(
    listPicker,
    /successMessage:\s*format\('listPicker\.moveSuccess', \{ list: targetList\.name \}\)/,
  );
  assert.doesNotMatch(listPicker, /successMessage:\s*`\$\{t\('contextMenu\.movedToList'\)\}/);

  assert.match(quickCapture, /toast\.success\(format\('capture\.taskCreateSuccessWithTitle', \{ title: captured\.title \}\)\)/);
  assert.doesNotMatch(quickCapture, /toast\.success\(`\$\{t\('task\.createSuccess'\)\}/);

  for (const source of [weeklyReview, paletteMutations]) {
    assert.doesNotMatch(source, /toast\.(success|info)\(`\$\{t\('review\.[^']+'\)\}:\s*\$\{[^}]+\}`/);
    assert.match(source, /format\('review\.shelvedToSomedayNamed'/);
  }

  assert.doesNotMatch(systemActions, /toast\.(success|info)\(`\$\{t\('[^']+'\)\}:\s*\$\{[^}]+\}`/);
  assert.match(systemActions, /format\('settings\.exportSavedToPath', \{ path: result\.export_path \}\)/);
  assert.match(systemActions, /format\('palette\.importDataResult', \{ count: result\.entities_created \}\)/);
  assert.match(systemActions, /format\('settings\.languageChanged', \{ locale: next \}\)/);

  const variableToastSources = [
    dangerZone,
    nativeCalendar,
    taskDetailLifecycle,
    swipeActions,
    taskListActions,
    snapshotActions,
    paletteMutations,
  ];
  for (const source of variableToastSources) {
    assert.doesNotMatch(
      source,
      /(?:toast\.(success|info)|showUndoToastWithRedo)\(`\$\{t\('[^']+'\)\}:\s*\$\{[^}]+\}`/,
    );
    assert.doesNotMatch(
      source,
      /persist:\s*\{ label: `\$\{t\('[^']+'\)\}:\s*\$\{[^}]+\}`/,
    );
  }

  assert.match(dangerZone, /format\('settings\.purgeCancelledResult', \{ count: result\.purged_count \}\)/);
  assert.match(dangerZone, /format\('settings\.dangerClearChangelogDoneCount', \{ count: result\.deleted \}\)/);
  assert.match(nativeCalendar, /format\('settings\.nativeCalendarSyncedSummary', \{\s*imported: result\.events_imported,\s*updated: result\.events_updated,\s*\}\)/);
  assert.match(nativeCalendar, /format\('settings\.nativeCalendarClearedCount', \{ count: deleted \}\)/);
  assert.match(taskDetailLifecycle, /format\('task\.status\.completedNamed', \{ title: task\.title \}\)/);
  assert.match(taskDetailLifecycle, /format\('task\.duplicatedNamed', \{ title: cloned\.title \}\)/);
  assert.match(swipeActions, /format\('task\.status\.completedNamed', \{ title: task\.title \}\)/);
  assert.match(taskListActions, /format\('task\.status\.completedNamed', \{ title: task\.title \}\)/);
  assert.match(taskListActions, /format\('task\.status\.cancelledNamed', \{ title: task\.title \}\)/);
  assert.match(snapshotActions, /format\('settings\.exportSavedToPath', \{ path: exportFileName \}\)/);
});
