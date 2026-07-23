import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readTypeScriptSources, repoRoot } from './shared.mjs';

test('TodayView is organized as a folder-backed subsystem with focused controller, content, section, and reorder modules', () => {
  const rootSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/TodayView.tsx'), 'utf8');
  const todayTreeSource = readTypeScriptSources(
    'app/src/components/TodayView.tsx',
    'app/src/components/today-view',
  );
  const contentSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/today-view/TodayViewContent.tsx'), 'utf8');
  const controllerSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/today-view/useTodayViewController.ts'), 'utf8');
  const sectionsSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/today-view/sections.tsx'), 'utf8');
  const dashboardSectionsSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/today-view/sections/DashboardSectionRenderer.tsx'), 'utf8');
  const overdueAlertCardSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/today-view/sections/cards/SectionOverdueAlertCard.tsx'), 'utf8');
  const dashboardActionsSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/today-view/sections/useDashboardSectionActions.ts'), 'utf8');
  const todayEventsSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/today-view/sections/TodayEventsSection.tsx'), 'utf8');
  const focusSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/today-view/FocusSection.tsx'), 'utf8');
  const focusActionsSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/today-view/useFocusReorderActions.ts'), 'utf8');
  const primitivesSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/today-view/primitives.tsx'), 'utf8');
  const orderingSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/today-view/taskOrdering.ts'), 'utf8');

  assert.match(rootSource, /import TodayViewContent from '\.\/today-view\/TodayViewContent';/, 'TodayView root should render a dedicated today-view content module');
  assert.match(rootSource, /import \{ useTodayViewController \} from '\.\/today-view\/useTodayViewController';/, 'TodayView root should delegate orchestration to a dedicated today-view controller module');
  assert.match(rootSource, /const controller = useTodayViewController\(/, 'TodayView root should remain a thin composition layer over the controller state');
  assert.match(contentSource, /export default function TodayViewContent\(/, 'today-view/TodayViewContent.tsx should own TodayView rendering');
  assert.match(controllerSource, /export function useTodayViewController\(/, 'today-view/useTodayViewController.ts should own TodayView query orchestration and derived state');
  assert.match(sectionsSource, /^export \{[^}]*DashboardSectionRenderer[^}]*\} from '\.\/sections\/DashboardSectionRenderer';$/m, 'today-view/sections.tsx should stay a pure export surface after folder extraction');
  assert.match(sectionsSource, /^export \{ TodayEventsSection \} from '\.\/sections\/TodayEventsSection';$/m, 'today-view/sections.tsx should re-export the today-events renderer from the sections subtree');
  assert.doesNotMatch(sectionsSource, /export function DashboardSectionRenderer\(|export function TodayEventsSection\(/, 'today-view/sections.tsx should not keep inline renderers after folder extraction');
  assert.match(dashboardSectionsSource, /export function DashboardSectionRenderer\(/, 'today-view/sections/DashboardSectionRenderer.tsx should own section dispatch and section rendering');
  assert.match(overdueAlertCardSource, /import \{ useDashboardSectionActions \} from '\.\.\/useDashboardSectionActions';/, 'Overdue alert card should delegate section-side mutations to a dedicated runtime hook');
  assert.doesNotMatch(dashboardSectionsSource, /updateTask\(|useMutation\(\{|useQueryClient\(/, 'DashboardSectionRenderer should not keep inline overdue-reschedule mutation ownership');
  assert.match(dashboardActionsSource, /export function useDashboardSectionActions\(/, 'today-view/sections/useDashboardSectionActions.ts should own dashboard section action wiring');
  assert.match(dashboardActionsSource, /useMutation(?:<[^>]+>)?\(\{/, 'Dashboard section runtime hook should own mutation wiring');
  assert.match(todayEventsSource, /export function TodayEventsSection\(/, 'today-view/sections/TodayEventsSection.tsx should own today-event rendering');
  assert.match(focusSource, /export function FocusSection\(/, 'today-view/FocusSection.tsx should own focus reordering UI and persistence');
  assert.match(focusSource, /import \{ useFocusReorderActions \} from '\.\/useFocusReorderActions';/, 'FocusSection should delegate reorder mutation ownership to a dedicated runtime hook');
  assert.doesNotMatch(focusSource, /useMutation\(\{|reorderCurrentFocusOpenTasks\(/, 'FocusSection should not keep inline reorder mutation ownership');
  assert.match(focusActionsSource, /export function useFocusReorderActions\(/, 'today-view/useFocusReorderActions.ts should own focus reorder mutation wiring');
  assert.match(focusActionsSource, /useMutation(?:<[^>]+>)?\(\{/, 'Focus reorder runtime hook should own mutation wiring');
  assert.match(primitivesSource, /export function SectionHeader\(/, 'today-view/primitives.tsx should own shared section header primitives');
  assert.match(primitivesSource, /export function StatCard\(/, 'today-view/primitives.tsx should own shared today metric card primitives');
  assert.match(orderingSource, /export function rankFallbackFocusTask\(/, 'today-view/taskOrdering.ts should expose shared today-task ordering helpers such as rankFallbackFocusTask');
  assert.match(orderingSource, /export function moveTaskId\(/, 'today-view/taskOrdering.ts should expose the shared moveTaskId helper for focus reorder');
  assert.match(todayTreeSource, /queryKey:\s*QUERY_KEYS\.todayEvents\(todayIso\)/, 'today-view controller tree should keep today-events under the canonical todayEvents query key factory');
});
