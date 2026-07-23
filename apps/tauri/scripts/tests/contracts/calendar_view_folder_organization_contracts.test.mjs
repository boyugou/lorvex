import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readTypeScriptSources, repoRoot } from './shared.mjs';

test('CalendarView is organized as a folder-backed subsystem with week grid, day panel, and event form modules', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/CalendarView.tsx'),
    'utf8',
  );
  const calendarViewControllerSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/useCalendarViewController.ts'),
    'utf8',
  );
  const calendarViewContentSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/CalendarViewContent.tsx'),
    'utf8',
  );
  const dayPanelIndexSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/day-panel/index.ts'),
    'utf8',
  );
  const monthGridLegacyPath = path.join(
    repoRoot,
    'app/src/components/calendar',
    'MonthGrid.tsx',
  );
  const monthGridSource = readTypeScriptSources('app/src/components/calendar/MonthGrid');
  const monthGridIndexSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/MonthGrid/index.tsx'),
    'utf8',
  );
  const monthGridRuntimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/monthGrid.runtime.ts'),
    'utf8',
  );
  const desktopMonthGridSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/MonthGrid/DesktopMonthGrid.tsx'),
    'utf8',
  );
  const mobileWeekGridSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/MonthGrid/MobileWeekGrid.tsx'),
    'utf8',
  );
  const weekGridSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/WeekGrid.tsx'),
    'utf8',
  );
  const weekTimelineGridSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/week-timeline/WeekTimelineGrid.tsx'),
    'utf8',
  );
  const weekDayColumnSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/week-timeline/WeekDayColumn.tsx'),
    'utf8',
  );
  const weekEventChipSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/week-timeline/WeekTimelineEventChip.tsx'),
    'utf8',
  );
  const weekTaskChipSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/week-timeline/WeekTimelineTaskChip.tsx'),
    'utf8',
  );
  const weekAllDayStripSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/week-timeline/WeekAllDayStrip.tsx'),
    'utf8',
  );
  const dayPanelSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/day-panel/DayPanel.tsx'),
    'utf8',
  );
  const dayPanelActionsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/day-panel/useDayPanelTaskActions.ts'),
    'utf8',
  );
  const dayEventRowSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/day-panel/DayEventRow.tsx'),
    'utf8',
  );
  const dayEventRowActionsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/day-panel/useDayEventRowActions.ts'),
    'utf8',
  );
  const dayTaskSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/day-panel/DayTask.tsx'),
    'utf8',
  );
  const eventFormIndexSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/event-form/index.ts'),
    'utf8',
  );
  const eventFormSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/event-form/EventForm.tsx'),
    'utf8',
  );
  const eventFormControllerSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/event-form/useEventFormController.ts'),
    'utf8',
  );
  const eventFormStateSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/event-form/state.ts'),
    'utf8',
  );
  const eventFormEffectsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/event-form/effects.ts'),
    'utf8',
  );
  const eventFormMutationsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/event-form/mutations.ts'),
    'utf8',
  );
  const eventFormSupportSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/event-form/support.ts'),
    'utf8',
  );
  const eventRecurrenceSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/event-form/EventRecurrenceFields.tsx'),
    'utf8',
  );
  const supportSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/viewSupport.ts'),
    'utf8',
  );
  const calendarTaskActionsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/calendar/useCalendarTaskActions.ts'),
    'utf8',
  );
  const calendarSources = readTypeScriptSources(
    'app/src/components/CalendarView.tsx',
    'app/src/components/calendar',
  );

  assert.match(rootSource, /import \{ CalendarViewContent \} from '\.\/calendar\/CalendarViewContent';/);
  assert.match(rootSource, /import \{ useCalendarViewController \} from '\.\/calendar\/useCalendarViewController';/);
  assert.match(rootSource, /const controller = useCalendarViewController\(/);
  assert.doesNotMatch(
    rootSource,
    /useQuery\(|useState\(|MonthGrid|WeekGrid|DayPanel|TaskDetail|cells\.map\(\(day, index\)/,
    'CalendarView root should stay focused on query/state/layout composition after extraction',
  );

  assert.match(calendarViewControllerSource, /export function useCalendarViewController\(/);
  assert.match(calendarViewControllerSource, /useQuery\(\{/);
  assert.match(calendarViewControllerSource, /queryKey: QUERY_KEYS\.calendarTasks\(from, to\)/);
  assert.match(calendarViewControllerSource, /queryKey: QUERY_KEYS\.calendarEvents\(from, to\)/);
  assert.match(calendarViewControllerSource, /const tasksByDate = useMemo\(\(\) => \{/);
  assert.match(calendarViewControllerSource, /const eventsByDate = useMemo\(\(\) => \{/);
  assert.match(calendarViewControllerSource, /export type CalendarViewController = ReturnType<typeof useCalendarViewController>;/);

  assert.match(calendarViewContentSource, /export function CalendarViewContent\(/);
  assert.match(calendarViewContentSource, /import \{ DayPanel \} from '\.\/day-panel';/);
  assert.match(calendarViewContentSource, /import \{ MonthGrid \} from '\.\/MonthGrid';/);
  assert.match(calendarViewContentSource, /import \{ WeekGrid \} from '\.\/WeekGrid';/);
  assert.match(calendarViewContentSource, /import \{ useCalendarTaskActions \} from '\.\/useCalendarTaskActions';/);
  assert.match(calendarViewContentSource, /const TaskDetail = lazy\(\(\) => import\('\.\.\/TaskDetail'\)\);/);
  assert.doesNotMatch(calendarViewContentSource, /getTasksByDateRange|getEventsByDateRange|getCalendarEventsUnified/);
  assert.doesNotMatch(calendarViewContentSource, /updateTask\(|useQueryClient\(/);
  assert.match(calendarTaskActionsSource, /export function useCalendarTaskActions\(/);
  assert.match(calendarTaskActionsSource, /updateTask\(/);

  assert.match(dayPanelIndexSource, /export \{ DayPanel \} from '\.\/DayPanel';/);
  assert.equal(
    fs.existsSync(monthGridLegacyPath),
    false,
    'obsolete MonthGrid.tsx should not exist beside the folder-backed MonthGrid subsystem',
  );
  assert.match(monthGridIndexSource, /import \{ DesktopMonthGrid \} from '\.\/DesktopMonthGrid';/);
  assert.match(monthGridIndexSource, /import \{ MobileWeekGrid \} from '\.\/MobileWeekGrid';/);
  assert.match(monthGridIndexSource, /from '\.\.\/monthGrid\.runtime';/);
  assert.match(monthGridIndexSource, /installMonthGridMediaRuntime\(/);
  assert.match(monthGridIndexSource, /readMonthGridNarrowMatch\(/);
  assert.match(monthGridSource, /export function MonthGrid\(/);
  assert.match(monthGridSource, /const cells: Array<number \| null> = \[/);
  assert.match(monthGridRuntimeSource, /export function readMonthGridNarrowMatch\(/);
  assert.match(monthGridRuntimeSource, /export function installMonthGridMediaRuntime\(/);
  assert.match(desktopMonthGridSource, /export function DesktopMonthGrid\(/);
  assert.match(desktopMonthGridSource, /useDesktopMonthLayout\(/);
  assert.match(desktopMonthGridSource, /useConfiguredDayContext\(/);
  assert.match(mobileWeekGridSource, /export function MobileWeekGrid\(/);
  assert.match(mobileWeekGridSource, /useConfiguredDayContext\(/);

  assert.match(weekGridSource, /export function WeekGrid\(/);
  assert.match(weekGridSource, /import \{ WeekTimelineGrid \} from '\.\/week-timeline\/WeekTimelineGrid';/);
  assert.match(weekGridSource, /return <WeekTimelineGrid \{\.\.\.props\} \/>;/);
  assert.doesNotMatch(weekGridSource, /completeTask\(|undoTaskLifecycle\(|showUndoToastWithRedo\(|useQueryClient\(/);
  assert.match(weekTimelineGridSource, /export function WeekTimelineGrid\(/);
  assert.match(weekTimelineGridSource, /import \{ WeekAllDayStrip \} from '\.\/WeekAllDayStrip';/);
  assert.match(weekTimelineGridSource, /import \{ WeekDayColumn \} from '\.\/WeekDayColumn';/);
  assert.match(weekTimelineGridSource, /import \{ WeekTimeAxis \} from '\.\/WeekTimeAxis';/);
  assert.match(weekTimelineGridSource, /resolveWeekTimelineDropTime\(/);
  assert.match(weekDayColumnSource, /export function WeekDayColumn\(/);
  assert.match(weekDayColumnSource, /import \{ WeekTimelineEventChip \} from '\.\/WeekTimelineEventChip';/);
  assert.match(weekDayColumnSource, /import \{ WeekTimelineTaskChip \} from '\.\/WeekTimelineTaskChip';/);
  assert.match(weekDayColumnSource, /computeWeekTimelineSlots\(/);
  assert.match(weekEventChipSource, /export function WeekTimelineEventChip\(/);
  assert.match(weekTaskChipSource, /export function WeekTimelineTaskChip\(/);
  assert.match(weekAllDayStripSource, /export function WeekAllDayStrip\(/);
  assert.doesNotMatch(weekTimelineGridSource, /completeTask\(|undoTaskLifecycle\(|showUndoToastWithRedo\(|useQueryClient\(/);

  assert.match(dayPanelSource, /export function DayPanel\(/);
  assert.match(dayPanelSource, /const eventFormSessionRef = useRef\(0\);/);
  assert.match(dayPanelSource, /import \{ DayEventRow \} from '\.\/DayEventRow';/);
  assert.match(dayPanelSource, /import \{ DayTask \} from '\.\/DayTask';/);
  assert.match(dayPanelSource, /import \{ EventForm \} from '\.\.\/event-form';/);
  assert.match(dayPanelSource, /import \{ useDayPanelTaskActions \} from '\.\/useDayPanelTaskActions';/);
  assert.doesNotMatch(dayPanelSource, /function DayEventRow\(|function DayTask\(/);
  assert.doesNotMatch(dayPanelSource, /completeTask\(|quickCapture\(|reopenTask\(|undoTaskLifecycle\(|showUndoToastWithRedo\(|updateTask\(/);
  assert.match(dayPanelActionsSource, /export function useDayPanelTaskActions\(/);

  assert.match(dayEventRowSource, /export (?:function DayEventRow\(|const DayEventRow = memo\(DayEventRowInner\))/);
  assert.match(dayEventRowSource, /import \{ useDayEventRowActions \} from '\.\/useDayEventRowActions';/);
  assert.doesNotMatch(dayEventRowSource, /useMutation\(\{/);
  assert.match(dayEventRowSource, /formatTimeRange\(/);
  assert.match(dayEventRowActionsSource, /export function useDayEventRowActions\(/);
  assert.match(dayEventRowActionsSource, /useMutation\(\{/);

  assert.match(dayTaskSource, /export (?:function DayTask\(|const DayTask = memo\(DayTaskInner\))/);
  assert.match(dayTaskSource, /completeLabelPrefix/);
  assert.match(dayTaskSource, /task\.recurrence \? RECURRENCE_SYMBOL : ''/);

  assert.match(eventFormIndexSource, /export \{ EventForm \} from '\.\/EventForm';/);
  assert.match(eventFormSource, /export function EventForm\(/);
  assert.match(eventFormSource, /useEventFormController\(/);
  assert.match(eventFormSource, /<EventRecurrenceFields/);
  assert.doesNotMatch(eventFormSource, /useMutation\(\{/);
  assert.doesNotMatch(eventFormSource, /WEEKDAY_OPTIONS\.map/);

  assert.match(eventFormControllerSource, /export function useEventFormController\(/);
  assert.match(eventFormControllerSource, /import \{ useEventFormEffects \} from '\.\/effects';/);
  assert.match(eventFormControllerSource, /import \{ useEventFormMutations \} from '\.\/mutations';/);
  assert.match(eventFormControllerSource, /import \{ useEventFormState \} from '\.\/state';/);
  assert.doesNotMatch(eventFormControllerSource, /useMutation\(\{|reportClientError\(|getPreference\(|normalizeTimezonePreference/);

  assert.match(eventFormStateSource, /export function useEventFormState\(/);
  assert.match(eventFormStateSource, /normalizeTimezonePreference/);
  assert.match(eventFormStateSource, /resolveTimezoneOptions/);
  assert.match(eventFormEffectsSource, /export function useEventFormEffects\(/);
  assert.match(eventFormEffectsSource, /reportClientError\(/);
  assert.match(eventFormEffectsSource, /getPreference\(/);
  assert.match(eventFormMutationsSource, /export function useEventFormMutations\(/);
  assert.match(eventFormMutationsSource, /useMutation\(\{/);
  assert.match(eventFormSupportSource, /export function buildEventPayload\(/);
  assert.match(eventFormSupportSource, /export function validateEventSubmission\(/);

  assert.match(eventRecurrenceSource, /export function EventRecurrenceFields\(/);
  assert.match(eventRecurrenceSource, /WEEKDAY_OPTIONS\.map/);
  assert.match(eventRecurrenceSource, /<AppSelect/);

  assert.match(supportSource, /export function reportCalendarError\(/);
  assert.match(supportSource, /export function reportCalendarTaskActionError\(/);
  assert.match(supportSource, /export const EVENT_COLORS = \[/);
  assert.match(calendarSources, /reportClientError\(/);
});

test('CalendarView contract rejects the removed flat MonthGrid entry', () => {
  const contractSource = fs.readFileSync(import.meta.filename, 'utf8');
  const forbiddenContractFragments = [
    ['app/src/components/calendar', 'MonthGrid.tsx'].join('/'),
    ['fs.existsSync', '(legacy)'].join(''),
    ['legacy single-file', 'shape'].join(' '),
  ];

  for (const fragment of forbiddenContractFragments) {
    assert.equal(
      contractSource.includes(fragment),
      false,
      `CalendarView contract should not preserve removed MonthGrid fallback fragment: ${fragment}`,
    );
  }
  assert.equal(
    fs.existsSync(path.join(repoRoot, 'app/src/components/calendar', 'MonthGrid.tsx')),
    false,
    'obsolete MonthGrid.tsx should not exist beside the folder-backed MonthGrid subsystem',
  );
});
