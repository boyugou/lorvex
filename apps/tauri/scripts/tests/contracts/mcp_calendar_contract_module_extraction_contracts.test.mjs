import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('server_contract calendar module delegates bounded domains to focused submodules', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'mcp-server/src/contract.rs'),
    'utf8',
  );
  const calendarModulePath = path.join(repoRoot, 'mcp-server/src/contract/calendar.rs');
  const calendarModuleSource = fs.readFileSync(calendarModulePath, 'utf8');
  const expectedModules = {
    events: ['AttendeeInput', 'CalendarEventTypeArg', 'CreateCalendarEventArgs'],
    exceptions: ['AddEventExceptionArgs', 'RemoveEventExceptionArgs'],
    ics: ['ExportCalendarIcsArgs'],
    links: ['LinkTaskToEventArgs', 'GetLinkedTasksForEventArgs'],
    provider: ['KnownProviderKind', 'LinkTaskToProviderEventArgs'],
    queries: ['GetCalendarEventArgs', 'GetCalendarEventsArgs', 'SearchCalendarEventsArgs'],
  };

  assert.match(
    rootSource,
    /mod calendar;/,
    'server_contract.rs should declare a dedicated calendar contract submodule',
  );
  assert.match(
    rootSource,
    /pub\(crate\) use calendar::\*;/,
    'server_contract.rs should re-export calendar contracts so downstream code keeps one import surface',
  );

  for (const moduleName of Object.keys(expectedModules)) {
    assert.match(
      calendarModuleSource,
      new RegExp(`pub\\(crate\\) use ${moduleName}::\\*;`),
      `server_contract/calendar.rs should re-export ${moduleName} calendar contracts`,
    );
  }

  for (const [moduleName, symbols] of Object.entries(expectedModules)) {
    const modulePath = path.join(
      repoRoot,
      'mcp-server/src/contract/calendar',
      `${moduleName}.rs`,
    );
    assert.ok(
      fs.existsSync(modulePath),
      `server_contract/calendar/${moduleName}.rs should own ${moduleName} calendar contracts`,
    );
    assert.match(
      calendarModuleSource,
      new RegExp(`mod ${moduleName};`),
      `calendar.rs should declare ${moduleName} submodule`,
    );

    const moduleSource = fs.readFileSync(modulePath, 'utf8');
    for (const symbol of symbols) {
      assert.match(
        moduleSource,
        new RegExp(`\\b${symbol}\\b`),
        `server_contract/calendar/${moduleName}.rs should own ${symbol}`,
      );
      assert.doesNotMatch(
        calendarModuleSource,
        new RegExp(`\\bstruct ${symbol}\\b|\\benum ${symbol}\\b|\\bfn ${symbol}\\b|\\bimpl ${symbol}\\b`),
        `calendar.rs should not keep inline ${symbol} definitions after bounded-domain extraction`,
      );
    }
  }
});
