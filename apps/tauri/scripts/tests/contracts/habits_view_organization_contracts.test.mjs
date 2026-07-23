import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('HabitsView delegates form card and action ownership to habits modules', () => {
  const habitsViewSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/HabitsView.tsx'),
    'utf8',
  );
  const addHabitFormSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/habits/AddHabitForm.tsx'),
    'utf8',
  );
  const habitCardSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/habits/HabitCard.tsx'),
    'utf8',
  );
  const habitDeleteSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/habits/useHabitDeleteAction.ts'),
    'utf8',
  );
  const habitMenuSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/habits/useHabitCardContextMenu.ts'),
    'utf8',
  );
  const habitContextMenuSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/habits/HabitContextMenu.tsx'),
    'utf8',
  );
  const dateWindowSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/habits/dateWindow.logic.ts'),
    'utf8',
  );

  assert.match(habitsViewSource, /import \{ AddHabitForm \} from '\.\/habits\/AddHabitForm';/);
  assert.match(habitsViewSource, /import \{ HabitCard \} from '\.\/habits\/HabitCard';/);
  assert.match(habitsViewSource, /import \{ HabitContextMenu \} from '\.\/habits\/HabitContextMenu';/);
  assert.match(habitsViewSource, /import \{ generateLast84Days \} from '\.\/habits\/dateWindow\.logic';/);
  assert.match(habitsViewSource, /import \{ useHabitDeleteAction \} from '\.\/habits\/useHabitDeleteAction';/);
  assert.match(habitsViewSource, /import \{ useHabitCardContextMenu \} from '\.\/habits\/useHabitCardContextMenu';/);
  assert.doesNotMatch(
    habitsViewSource,
    /createHabit\(|deleteHabit\(|confirm\(|ValidatedField|recent_completion_dates|completion_rate_30d|<ContextMenu|from '\.\/context-menu\/ContextMenu'|MS_PER_DAY/,
    'HabitsView should stay a composition shell instead of owning form, delete, or card rendering internals',
  );

  assert.match(addHabitFormSource, /createHabit\(/);
  assert.match(addHabitFormSource, /ValidatedField/);
  assert.match(addHabitFormSource, /normalizeHabitTargetCountInput/);
  assert.match(
    addHabitFormSource,
    /defineEntityHooks\(\{\s*entity:\s*'habit'/s,
    'AddHabitForm should route create invalidation through entity hooks instead of hand-wiring query invalidation',
  );

  assert.match(habitCardSource, /recent_completion_dates/);
  assert.match(habitCardSource, /role="img"/);
  assert.match(habitCardSource, /aria-describedby=\{decrementDisabled \? decrementHintId : undefined\}/);

  assert.match(habitDeleteSource, /deleteHabit\(/);
  assert.match(habitDeleteSource, /triggerElement/);
  assert.match(
    habitDeleteSource,
    /defineEntityHooks\(\{\s*entity:\s*'habit'/s,
    'useHabitDeleteAction should route delete invalidation through entity hooks instead of hand-wiring query invalidation',
  );

  assert.match(habitMenuSource, /event\.preventDefault\(\)/);
  assert.match(habitMenuSource, /triggerElement/);

  assert.match(habitContextMenuSource, /<ContextMenu/);
  assert.match(habitContextMenuSource, /onDelete\(target, trigger\)/);

  assert.match(dateWindowSource, /export function generateLast84Days/);
  assert.match(dateWindowSource, /MS_PER_DAY/);
});
