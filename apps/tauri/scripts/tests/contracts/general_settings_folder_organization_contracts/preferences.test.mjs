import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from '../shared.mjs';

test('general settings preferences subtree delegates focused panels and shared catalogs', () => {
  const preferencesSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/general/GeneralPreferencesSection.tsx'),
    'utf8',
  );
  const preferencesCatalogSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/general/catalog.ts'),
    'utf8',
  );
  const sidebarPanelSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/general/SidebarModulesPanel.tsx'),
    'utf8',
  );
  const workflowPanelSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/general/WorkflowPreferencesPanel.tsx'),
    'utf8',
  );
  const desktopPanelSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/general/DesktopBehaviorPanel.tsx'),
    'utf8',
  );
  const advancedPanelSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/general/AdvancedPreferencesPanel.tsx'),
    'utf8',
  );
  const habitRemindersPanelSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/general/HabitRemindersPanel.tsx'),
    'utf8',
  );
  const habitReminderActionsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/general/useHabitReminderActions.ts'),
    'utf8',
  );

  assert.match(
    preferencesSource,
    /import \{ SidebarModulesPanelContent \} from '\.\/SidebarModulesPanel';/,
    'General preferences root should delegate sidebar toggles to a dedicated panel module (content variant)',
  );
  assert.match(
    preferencesSource,
    /import \{ WorkflowPreferencesPanelContent \} from '\.\/WorkflowPreferencesPanel';/,
    'General preferences root should delegate workflow settings to a dedicated panel module (content variant)',
  );
  assert.match(
    preferencesSource,
    /import \{ DesktopBehaviorPanelContent \} from '\.\/DesktopBehaviorPanel';/,
    'General preferences root should delegate desktop behavior settings to a dedicated panel module (content variant)',
  );
  assert.match(
    preferencesSource,
    /import \{ AdvancedPreferencesPanel \} from '\.\/AdvancedPreferencesPanel';/,
    'General preferences root should delegate advanced scheduling and timezone settings to a dedicated panel module',
  );
  assert.match(
    preferencesSource,
    /import type \{ GeneralPreferencesSectionProps \} from '\.\/types';/,
    'General preferences root should source its prop contract from the shared general types module',
  );
  assert.doesNotMatch(
    preferencesSource,
    /const WEEKLY_REVIEW_DAY_OPTIONS:|const DESKTOP_CLOSE_ACTION_OPTIONS:|const SIDEBAR_MODULE_OPTIONS:|type="range"|settings\.sidebarPrimarySection|settings\.launchOnLogin|settings\.weeklyReviewDay/,
    'General preferences root should stay focused on composition and small shared sections after panel extraction',
  );

  assert.match(
    preferencesCatalogSource,
    /export const WEEKLY_REVIEW_DAY_OPTIONS:/,
    'General preferences catalog should own weekly review day options',
  );
  assert.match(
    preferencesCatalogSource,
    /export const DESKTOP_CLOSE_ACTION_OPTIONS:/,
    'General preferences catalog should own desktop close-action select options',
  );
  assert.match(
    preferencesCatalogSource,
    /export const SIDEBAR_MODULE_OPTIONS:/,
    'General preferences catalog should own sidebar module toggles',
  );

  assert.match(
    sidebarPanelSource,
    /SIDEBAR_MODULE_OPTIONS\.filter\(\((?:option|o)\) => (?:option|o)\.section === 'primary'\)/,
    'Sidebar modules panel should render primary sidebar toggles from the shared catalog',
  );
  assert.match(
    sidebarPanelSource,
    /SIDEBAR_MODULE_OPTIONS\.filter\(\((?:option|o)\) => (?:option|o)\.section === 'secondary'\)/,
    'Sidebar modules panel should render secondary sidebar toggles from the shared catalog',
  );

  assert.match(
    workflowPanelSource,
    /<TimeInput[\s\S]*value=\{workingHoursStart\}/,
    'Workflow panel should own working-hours start input',
  );
  assert.match(
    workflowPanelSource,
    /<TimeInput[\s\S]*value=\{workingHoursEnd\}/,
    'Workflow panel should own working-hours end input',
  );
  assert.match(
    workflowPanelSource,
    /settings\.weekStartsOn|settings\.weekStartMonday/,
    'Workflow panel should own week-start day controls',
  );

  assert.match(
    desktopPanelSource,
    /DESKTOP_CLOSE_ACTION_OPTIONS\.map\(/,
    'Desktop behavior panel should render close-action options from the shared catalog',
  );
  assert.match(
    desktopPanelSource,
    /t\(trayIconTitleKey\)|t\(trayIconDescKey\)|t\(trayIconVisibleKey\)|t\(trayIconHiddenKey\)/,
    'Desktop behavior panel should own tray copy-key rendering',
  );

  assert.match(
    advancedPanelSource,
    /WEEKLY_REVIEW_DAY_OPTIONS\.map\(/,
    'Advanced preferences panel should render weekly review day options from the shared catalog',
  );
  assert.match(
    advancedPanelSource,
    /settings\.timezone|settings\.morningBriefingTime/,
    'Advanced preferences panel should own timezone and review scheduling UI',
  );
  assert.match(
    habitRemindersPanelSource,
    /import \{ useHabitReminderActions \} from '\.\/useHabitReminderActions';/,
    'Habit reminders panel should delegate reminder mutations to a dedicated runtime hook',
  );
  assert.doesNotMatch(
    habitRemindersPanelSource,
    /useMutation\(\{/,
    'Habit reminders panel should not keep inline mutation ownership',
  );
  assert.match(
    habitReminderActionsSource,
    /export function useHabitReminderActions\(/,
    'Habit reminder mutations should live in a dedicated runtime hook',
  );
  assert.match(
    habitReminderActionsSource,
    /useMutation\(\{/,
    'Habit reminder runtime hook should own mutation wiring',
  );
});
