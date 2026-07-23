import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('calendar subscriptions settings delegate mutation ownership to a dedicated runtime hook', () => {
  const panelSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/calendar/CalendarSubscriptionsPanel.tsx'),
    'utf8',
  );
  const actionsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/calendar/useCalendarSubscriptionActions.ts'),
    'utf8',
  );

  assert.match(
    panelSource,
    /import \{ useCalendarSubscriptionActions \} from '\.\/useCalendarSubscriptionActions';/,
    'Calendar subscriptions panel should delegate mutation ownership to a dedicated runtime hook',
  );
  assert.doesNotMatch(
    panelSource,
    /useMutation\(\{/,
    'Calendar subscriptions panel should not keep inline mutation ownership',
  );

  assert.match(
    actionsSource,
    /export function useCalendarSubscriptionActions\(/,
    'Calendar subscriptions runtime should expose a dedicated action hook',
  );
  assert.match(
    actionsSource,
    /useMutation\(\{/,
    'Calendar subscriptions runtime hook should own mutation wiring',
  );
});

test('calendar subscription settings mirror the HTTPS-only fetch safety boundary', () => {
  const panelSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/calendar/CalendarSubscriptionsPanel.tsx'),
    'utf8',
  );
  const actionsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/calendar/useCalendarSubscriptionActions.ts'),
    'utf8',
  );
  const englishLocale = fs.readFileSync(path.join(repoRoot, 'app/src/locales/en.json'), 'utf8');

  assert.match(actionsSource, /trimmedUrl\.startsWith\('https:\/\/'\)/);
  assert.doesNotMatch(actionsSource, /trimmedUrl\.startsWith\('http:\/\/'\)/);
  assert.doesNotMatch(actionsSource, /trimmedUrl\.startsWith\('webcal:\/\/'\)/);

  assert.match(panelSource, /trimmedNewUrl\.startsWith\('https:\/\/'\)/);
  assert.doesNotMatch(panelSource, /trimmedNewUrl\.startsWith\('http:\/\/'\)/);
  assert.doesNotMatch(panelSource, /trimmedNewUrl\.startsWith\('webcal:\/\/'\)/);

  assert.match(englishLocale, /"settings\.calendarSubUrlError": "URL must start with https:\/\/"/);
  assert.doesNotMatch(englishLocale, /URL must start with https:\/\/, http:\/\/, or webcal:\/\//);
});
