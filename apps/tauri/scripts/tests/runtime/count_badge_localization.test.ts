import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';

const ROOT = process.cwd();

test('count-bearing UI surfaces avoid host-locale toLocaleString and raw count badges', () => {
  const kanban = readFileSync(join(ROOT, 'app', 'src', 'components', 'KanbanView.tsx'), 'utf8');
  const upcoming = readFileSync(join(ROOT, 'app', 'src', 'components', 'UpcomingView.tsx'), 'utf8');
  const todayPrimitives = readFileSync(join(ROOT, 'app', 'src', 'components', 'today-view', 'primitives.tsx'), 'utf8');
  const dailyReview = readFileSync(join(ROOT, 'app', 'src', 'components', 'DailyReviewView.tsx'), 'utf8');
  const popoverEventItem = readFileSync(join(ROOT, 'app', 'src', 'components', 'popover-window', 'PopoverEventItem.tsx'), 'utf8');
  const weeklyReview = readFileSync(join(ROOT, 'app', 'src', 'components', 'weekly-review', 'WeeklyReviewContent.tsx'), 'utf8');
  const reviewSection = readFileSync(join(ROOT, 'app', 'src', 'components', 'weekly-review', 'content', 'ReviewSection.tsx'), 'utf8');
  const weeklyStatCard = readFileSync(join(ROOT, 'app', 'src', 'components', 'weekly-review', 'content', 'StatCard.tsx'), 'utf8');
  const lookingAhead = readFileSync(join(ROOT, 'app', 'src', 'components', 'weekly-review', 'content', 'LookingAheadSection.tsx'), 'utf8');
  const overdueSeverity = readFileSync(join(ROOT, 'app', 'src', 'components', 'weekly-review', 'content', 'OverdueSeveritySection.tsx'), 'utf8');
  const deferredTaskRow = readFileSync(join(ROOT, 'app', 'src', 'components', 'weekly-review', 'content', 'DeferredTaskRow.tsx'), 'utf8');
  const stalledListRow = readFileSync(join(ROOT, 'app', 'src', 'components', 'weekly-review', 'content', 'StalledListRow.tsx'), 'utf8');
  const listViewHeader = readFileSync(join(ROOT, 'app', 'src', 'components', 'list-view', 'ListViewHeader.tsx'), 'utf8');
  const completedTasksSection = readFileSync(join(ROOT, 'app', 'src', 'components', 'list-view', 'CompletedTasksSection.tsx'), 'utf8');
  const commandPalette = readFileSync(join(ROOT, 'app', 'src', 'components', 'CommandPalette.tsx'), 'utf8');
  const someday = readFileSync(join(ROOT, 'app', 'src', 'components', 'SomedayView.tsx'), 'utf8');
  const recurring = readFileSync(join(ROOT, 'app', 'src', 'components', 'RecurringTasksView.tsx'), 'utf8');
  const monthGrid = [
    'index.tsx',
    'DesktopMonthGrid.tsx',
    'MobileWeekGrid.tsx',
    'pills.tsx',
  ].map((file) =>
    readFileSync(join(ROOT, 'app', 'src', 'components', 'calendar', 'MonthGrid', file), 'utf8'),
  ).join('\n');
  const weekGrid = readFileSync(join(ROOT, 'app', 'src', 'components', 'calendar', 'WeekGrid.tsx'), 'utf8');
  const popoverWindow = readFileSync(join(ROOT, 'app', 'src', 'components', 'popover-window', 'PopoverWindowContent.tsx'), 'utf8');
  const popoverTaskItem = readFileSync(join(ROOT, 'app', 'src', 'components', 'popover-window', 'PopoverTaskItem.tsx'), 'utf8');
  const habitReminders = readFileSync(join(ROOT, 'app', 'src', 'components', 'settings', 'general', 'HabitRemindersPanel.tsx'), 'utf8');
  const taskRelations = readFileSync(join(ROOT, 'app', 'src', 'components', 'task-detail', 'content', 'TaskDetailRelations.tsx'), 'utf8');
  const timeHorizonPicker = readFileSync(join(ROOT, 'app', 'src', 'components', 'ui', 'TimeHorizonPicker.tsx'), 'utf8');
  const syncDiagnostics = readFileSync(join(ROOT, 'app', 'src', 'components', 'settings', 'assistant', 'sync-settings', 'SyncDiagnosticsPanel.tsx'), 'utf8');
  const syncMethodCard = readFileSync(join(ROOT, 'app', 'src', 'components', 'settings', 'assistant', 'sync-settings', 'SyncMethodCard.tsx'), 'utf8');
  const taskChecklistEditor = readFileSync(join(ROOT, 'app', 'src', 'components', 'task-detail', 'TaskChecklistEditor.tsx'), 'utf8');
  const todayHabits = readFileSync(join(ROOT, 'app', 'src', 'components', 'today-view', 'sections', 'TodayHabitsSection.tsx'), 'utf8');
  const todayEvents = readFileSync(join(ROOT, 'app', 'src', 'components', 'today-view', 'sections', 'TodayEventsSection.tsx'), 'utf8');
  const todayHeader = readFileSync(join(ROOT, 'app', 'src', 'components', 'today-view', 'TodayHeader.tsx'), 'utf8');

  assert.doesNotMatch(kanban, /<span>\{tasks\.length\}<\/span>/);
  assert.doesNotMatch(upcoming, /\{overdueTasks\.length\}<\/span>/);
  assert.doesNotMatch(upcoming, /\{itemCount\}<\/span>/);
  assert.doesNotMatch(todayPrimitives, /toLocaleString\(/);
  assert.doesNotMatch(weeklyStatCard, /toLocaleString\(/);
  assert.doesNotMatch(dailyReview, /\+\{daySummary\.completedTasks\.length - 8\}/);
  assert.doesNotMatch(dailyReview, /\{controller\.pastReviews\.length\}<\/span>/);
  assert.doesNotMatch(dailyReview, /`0\$\{c\.t\('dailyReview\.minute'\)\}`/);
  assert.doesNotMatch(dailyReview, /`\$\{m\}\$\{c\.t\('dailyReview\.minute'\)\}`/);
  assert.doesNotMatch(dailyReview, /`\$\{h\}\$\{c\.t\('dailyReview\.hour'\)\}/);
  assert.doesNotMatch(dailyReview, /aria-label=\{`\$\{c\.t\('dailyReview\.(mood|energy)'\)\} \$\{[a-z]+\}`\}/);
  assert.doesNotMatch(popoverEventItem, /replace\('\{0\}', String\(minutesUntil\)\)/);
  assert.doesNotMatch(weeklyReview, /\+\s*\{review\.someday_items\.length - 10\}/);
  assert.doesNotMatch(weeklyReview, /\{review\.overdue_count\}\)/);
  assert.doesNotMatch(reviewSection, /\{badge\}/);
  assert.doesNotMatch(weeklyStatCard, /\{trend\.value > 0 \? '\+' : ''\}\{trend\.value\}/);
  assert.doesNotMatch(lookingAhead, /\+\s*\{upcomingTasks\.length - 10\}/);
  assert.doesNotMatch(lookingAhead, /\+\s*\{events\.length - 8\}/);
  assert.doesNotMatch(overdueSeverity, /\{group\.tasks\.length\}/);
  assert.doesNotMatch(overdueSeverity, /\+\s*\{totalOverdue - groups\.reduce/);
  assert.doesNotMatch(deferredTaskRow, /↻\{task\.defer_count\}/);
  assert.doesNotMatch(stalledListRow, /\(\{daysAgo\}\{t\('time\.daysAgo'\)\}\)/);
  assert.doesNotMatch(listViewHeader, /\{openTasks\.length\}<\/span>/);
  assert.doesNotMatch(completedTasksSection, /replace\('\{count\}', String\(hidden\.length\)\)/);
  assert.doesNotMatch(commandPalette, /replace\('\{count\}', String\(results\.length\)\)/);
  assert.doesNotMatch(someday, /\{controller\.tasks\.length\}<\/span>/);
  assert.doesNotMatch(someday, /\{section\.tasks\.length\}<\/span>/);
  assert.doesNotMatch(recurring, /\{total\}<\/span>/);
  assert.doesNotMatch(recurring, /\{tasks\.length\}<\/span>/);
  assert.doesNotMatch(monthGrid, /\{openTasks\.length \+ dayEvents\.length\}/);
  assert.doesNotMatch(monthGrid, /<CheckIcon className="w-2 h-2" \/>\{completedTasks\.length\}/);
  assert.doesNotMatch(monthGrid, /\+\{totalHidden\} \{t\('calendar\.more'\)\}/);
  assert.doesNotMatch(weekGrid, /\{completedTasks\.length\}<\/span>/);
  assert.doesNotMatch(weekGrid, /formatDurationCompact\(task\.estimated_minutes, t\('common\.hourShort'\), t\('common\.min'\)\)/);
  assert.doesNotMatch(popoverWindow, /\+\{sortedEvents\.length - 4\}/);
  assert.doesNotMatch(popoverWindow, /formatDurationCompact\(totalDurationMinutes, t\('common\.hourShort'\), t\('common\.min'\)\)/);
  assert.doesNotMatch(popoverTaskItem, /\{task\.estimated_minutes\}\{t\('common\.min'\)\}/);
  assert.doesNotMatch(habitReminders, /replace\('\{count\}', String\(slotCount\)\)/);
  assert.doesNotMatch(taskRelations, /replace\('\{count\}',\s*String\(dependsOnIds\.length\)\)/);
  assert.doesNotMatch(taskRelations, /replace\('\{count\}',\s*String\(blocksIds\.length\)\)/);
  assert.doesNotMatch(timeHorizonPicker, /replace\('\{count\}', String\(opt\)\)/);
  assert.doesNotMatch(syncDiagnostics, /String\(syncStatus\.(pending_count|retrying_count|failed_count|tombstone_count|conflict_log_count)\)/);
  assert.doesNotMatch(syncMethodCard, /String\(lastSyncRunResult\.summary\.(pushed|pulledRemoteEvents|applied)\)/);
  assert.doesNotMatch(syncMethodCard, /\{syncProgress\.current\} \/ \{syncProgress\.total\}/);
  assert.doesNotMatch(taskChecklistEditor, /return `\$\{completed\}\/\$\{checklistItems\.length\}`/);
  assert.doesNotMatch(todayHabits, /\$\{completedCount\}\/\$\{habits\.length\}/);
  assert.doesNotMatch(todayHabits, /\{habit\.completions_today\}\/\{habit\.target_count\}/);
  assert.doesNotMatch(todayHabits, /🔥 \{habit\.current_streak\}/);
  assert.doesNotMatch(todayEvents, /replace\('\{0\}', String\(minutesUntil\)\)/);
  assert.doesNotMatch(todayHeader, /\{stats\.completed_today\}\/\{total\}/);
});
