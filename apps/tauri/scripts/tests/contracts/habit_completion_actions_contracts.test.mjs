import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('habit completion surfaces delegate optimistic mutation ownership to dedicated action hooks', () => {
  const habitsViewSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/HabitsView.tsx'),
    'utf8',
  );
  const todayHabitsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/today-view/sections/TodayHabitsSection.tsx'),
    'utf8',
  );
  const habitActionsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/habits/useHabitCompletionActions.ts'),
    'utf8',
  );

  assert.match(
    habitsViewSource,
    /import \{ useHabitStatsCompletionActions \} from '\.\/habits\/useHabitCompletionActions';/,
    'HabitsView should delegate optimistic completion mutations to a dedicated habits runtime hook',
  );
  assert.doesNotMatch(
    habitsViewSource,
    /adjustHabitCompletion\(/,
    'HabitsView should not keep inline completion mutation ownership',
  );

  assert.match(
    todayHabitsSource,
    /import \{ useTodayHabitCompletionActions \} from ['"](?:@\/components\/habits\/useHabitCompletionActions|\.\.\/\.\.\/habits\/useHabitCompletionActions)['"];/,
    'TodayHabitsSection should delegate optimistic completion mutations to the shared habits runtime hook',
  );
  assert.doesNotMatch(
    todayHabitsSource,
    /adjustHabitCompletion\(/,
    'TodayHabitsSection should not keep inline completion mutation ownership',
  );
  assert.match(
    todayHabitsSource,
    /aria-label=\{completionButtonLabel\}/,
    'Today habit completion control should expose a specific accessible name',
  );
  assert.match(
    todayHabitsSource,
    /aria-label=\{incrementButtonLabel\}/,
    'Today accumulative habit increment control should expose a specific accessible name',
  );
  assert.match(
    todayHabitsSource,
    /aria-label=\{completionButtonLabel\}[\s\S]*className=\{`[^`]*focus-ring-soft/s,
    'Today habit completion button should keep visible keyboard focus styling',
  );
  assert.match(
    todayHabitsSource,
    /aria-label=\{incrementButtonLabel\}[\s\S]*className="[^"]*focus-ring-soft/s,
    'Today habit increment button should keep visible keyboard focus styling',
  );

  assert.match(
    habitActionsSource,
    /function useHabitCompletionCollectionActions(?:<[^>]+>)?\(/,
    'Shared habits runtime should centralize optimistic toggle behavior behind one reusable collection hook',
  );
  assert.match(
    habitActionsSource,
    /export function useHabitStatsCompletionActions\(/,
    'Shared habits runtime should expose a stats-surface completion hook',
  );
  assert.match(
    habitActionsSource,
    /export function useTodayHabitCompletionActions\(/,
    'Shared habits runtime should expose a today-surface completion hook',
  );
  assert.match(
    habitActionsSource,
    /useMutation\(\{/,
    'Shared habits runtime should own mutation wiring',
  );
});
