import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readTypeScriptSources, repoRoot } from './shared.mjs';

test('TaskMetadataEditor is organized as a folder-backed subsystem with shared helpers and focused field modules', () => {
  const gridRootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/metadata-editor/TaskSecondaryMetaFields.tsx'),
    'utf8',
  );
  const editableGridSource = readTypeScriptSources(
    'app/src/components/task-detail/metadata-editor/editable-grid',
  );
  const unifiedMetaSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/metadata-editor/TaskUnifiedMetaCard.tsx'),
    'utf8',
  );
  const dueTimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/metadata-editor/editable-grid/DueTimeField.tsx'),
    'utf8',
  );
  const remindersSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/metadata-editor/editable-grid/RemindersField.tsx'),
    'utf8',
  );
  const recurrenceSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/metadata-editor/RecurrenceField.tsx'),
    'utf8',
  );
  const sharedSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/metadata-editor/shared.ts'),
    'utf8',
  );
  const primitivesSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/metadata-editor/primitives.tsx'),
    'utf8',
  );
  const reminderActionsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/metadata-editor/editable-grid/useTaskReminderActions.ts'),
    'utf8',
  );

  assert.equal(
    fs.existsSync(path.join(repoRoot, 'app/src/components/task-detail/TaskMetadataEditor.tsx')),
    false,
    'TaskMetadataEditor should not keep a root re-export alias',
  );
  assert.doesNotMatch(
    gridRootSource,
    /TaskEditableMetaGrid/,
    'TaskSecondaryMetaFields should not reintroduce the retired TaskEditableMetaGrid alias',
  );
  assert.doesNotMatch(
    gridRootSource,
    /TaskQuickDateRow/,
    'TaskSecondaryMetaFields should not reintroduce a dedicated TaskQuickDateRow module (quick-date chips now live inside TaskUnifiedMetaCard)',
  );
  assert.match(
    gridRootSource,
    /import RecurrenceField from '\.\/RecurrenceField';/,
    'TaskSecondaryMetaFields should render recurrence editing through a dedicated module',
  );
  assert.doesNotMatch(
    gridRootSource,
    /TaskTemporalFields/,
    'TaskSecondaryMetaFields should not reintroduce the retired combined temporal field module',
  );
  assert.match(
    gridRootSource,
    /import \{ DueTimeField \} from '\.\/editable-grid\/DueTimeField';/,
    'TaskSecondaryMetaFields should delegate due-time editing to a focused editable-grid module',
  );
  assert.match(
    gridRootSource,
    /import \{ RemindersField \} from '\.\/editable-grid\/RemindersField';/,
    'TaskSecondaryMetaFields should delegate reminder editing to a focused editable-grid module',
  );
  assert.match(
    gridRootSource,
    /import \{ TaskMetricsFields \} from '\.\/editable-grid\/TaskMetricsFields';/,
    'TaskSecondaryMetaFields should delegate derived metric fields to a focused editable-grid module',
  );
  assert.match(
    recurrenceSource,
    /export default function RecurrenceField/,
    'Task recurrence editing should live in a dedicated module',
  );
  assert.match(
    sharedSource,
    /export function parseRecurrence/,
    'TaskMetadataEditor shared recurrence helpers should live in a dedicated support module',
  );
  assert.match(
    primitivesSource,
    /export function InlineEditField/,
    'TaskMetadataEditor inline editor primitives should live in a dedicated module',
  );
  assert.match(
    unifiedMetaSource,
    /buildDueDatePatch\(task, date\)/,
    'TaskUnifiedMetaCard should own primary due-date editing',
  );
  assert.match(
    unifiedMetaSource,
    /onSave\(\{ planned_date: date \}\)/,
    'TaskUnifiedMetaCard should own primary planned-date editing',
  );
  assert.match(
    dueTimeSource,
    /buildDueTimePatch\(task, value, dayContext\.todayYmd\)/,
    'DueTimeField should own secondary due-time patch construction',
  );
  assert.match(
    remindersSource,
    /import \{ useTaskReminderActions \} from '\.\/useTaskReminderActions';/,
    'RemindersField should delegate reminder transport/query ownership to a dedicated hook',
  );
  assert.doesNotMatch(
    remindersSource,
    /addTaskReminder\(|removeTaskReminder\(|invalidateTaskReminderQueries\(/,
    'RemindersField should not keep reminder transport or invalidation inline',
  );
  assert.match(
    editableGridSource,
    /export function TaskMetricsFields/,
    'TaskMetadataEditor editable-grid subtree should own derived metric rendering',
  );
  assert.match(
    reminderActionsSource,
    /export function useTaskReminderActions\(/,
    'Task reminder query and mutation ownership should live in a dedicated editable-grid hook',
  );
  assert.match(
    reminderActionsSource,
    /getTaskReminders\(|addTaskReminder\(|removeTaskReminder\(|invalidateTaskReminderQueries\(/,
    'Task reminder hook should own reminder query, mutation, and invalidation wiring',
  );
});
