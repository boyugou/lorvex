import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';

import {
  beginDiagnosticsRefreshRequest,
  buildDiagnosticsRawFilters,
  buildConflictLogQueryConfig,
  buildDiagnosticsDeviceIdsQueryConfig,
  createDiagnosticsConflictLogRefetchController,
  createDiagnosticsFilterIntentController,
  createDiagnosticsPanelFilterEffectController,
  createDiagnosticsRefreshCoordinator,
  DEFAULT_DIAGNOSTICS_TIME_WINDOW,
  filterDiagnosticsRecentSyncEvents,
  loadFilteredRecentSyncEvents,
  readDiagnosticsConflictLogEntries,
  resolveDiagnosticsFilters,
  resolveDiagnosticsSinceIso,
  shouldIncludeDiagnosticsErrorLogs,
} from '../../../app/src/components/settings/data/diagnostics.logic';
import { buildRecentLogs } from '../../../app/src/components/settings/controller/data/diagnostics/recentLogs';
import { SYNC_OUTBOX_MAX_RETRIES } from '../../../app/src/lib/ipc/sync';
import { QUERY_KEYS } from '../../../app/src/lib/query/queryKeys';
import { STALE_DEFAULT, STALE_LONG } from '../../../app/src/lib/query/timing';

const ROOT = process.cwd();
const FIXED_NOW_MS = Date.UTC(2026, 3, 23, 5, 30, 0);

test('resolveDiagnosticsSinceIso keeps rolling hour/day/week windows anchored to the current wall clock', () => {
  assert.equal(
    resolveDiagnosticsSinceIso('hour', FIXED_NOW_MS),
    '2026-04-23T04:30:00.000Z',
  );
  assert.equal(
    resolveDiagnosticsSinceIso('day', FIXED_NOW_MS),
    '2026-04-22T05:30:00.000Z',
  );
  assert.equal(
    resolveDiagnosticsSinceIso('week', FIXED_NOW_MS),
    '2026-04-16T05:30:00.000Z',
  );
  assert.equal(resolveDiagnosticsSinceIso('all', FIXED_NOW_MS), null);
});

test('resolveDiagnosticsFilters preserves the rolling boundary and fails closed for blank device scope', () => {
  assert.deepEqual(
    resolveDiagnosticsFilters({
      timeWindow: DEFAULT_DIAGNOSTICS_TIME_WINDOW,
      sourceDeviceId: null,
    }, FIXED_NOW_MS),
    {
      sinceIso: '2026-04-22T05:30:00.000Z',
      sourceDeviceId: null,
    },
  );
  assert.deepEqual(
    resolveDiagnosticsFilters({
      timeWindow: 'hour',
      sourceDeviceId: 'device-123',
    }, FIXED_NOW_MS),
    {
      sinceIso: '2026-04-23T04:30:00.000Z',
      sourceDeviceId: 'device-123',
    },
  );
});

test('buildDiagnosticsRawFilters preserves rolling intent so panel and refresh can resolve against the same live clock', () => {
  const rawFilters = buildDiagnosticsRawFilters({
    timeWindow: 'hour',
    sourceDeviceId: 'device-123',
  });

  assert.deepEqual(rawFilters, {
    timeWindow: 'hour',
    sourceDeviceId: 'device-123',
  });
  assert.deepEqual(
    resolveDiagnosticsFilters(rawFilters, FIXED_NOW_MS),
    {
      sinceIso: '2026-04-23T04:30:00.000Z',
      sourceDeviceId: 'device-123',
    },
  );
  assert.deepEqual(
    resolveDiagnosticsFilters(rawFilters, FIXED_NOW_MS + 45_000),
    {
      sinceIso: '2026-04-23T04:30:45.000Z',
      sourceDeviceId: 'device-123',
    },
  );
});

test('diagnostics filter intent controller resolves the latest picker state at refresh time', () => {
  const controller = createDiagnosticsFilterIntentController();

  assert.deepEqual(controller.resolve(FIXED_NOW_MS), {
    sinceIso: '2026-04-22T05:30:00.000Z',
    sourceDeviceId: null,
  });

  controller.setFilters(buildDiagnosticsRawFilters({
    timeWindow: 'hour',
    sourceDeviceId: 'device-123',
  }));

  assert.deepEqual(controller.getFilters(), {
    timeWindow: 'hour',
    sourceDeviceId: 'device-123',
  });
  assert.deepEqual(controller.resolve(FIXED_NOW_MS + 45_000), {
    sinceIso: '2026-04-23T04:30:45.000Z',
    sourceDeviceId: 'device-123',
  });
});

test('diagnostics panel filter effect pushes filter intent before triggering post-mount refreshes', () => {
  const controller = createDiagnosticsPanelFilterEffectController();
  const filters = buildDiagnosticsRawFilters({
    timeWindow: 'hour',
    sourceDeviceId: 'device-123',
  });
  const calls: string[] = [];

  controller.apply({
    filters,
    syncNow: () => {
      calls.push('sync-now');
    },
    setFilters: (next) => {
      calls.push(`set:${next.timeWindow}:${next.sourceDeviceId}`);
    },
    refresh: () => {
      calls.push('refresh');
    },
  });
  controller.apply({
    filters,
    syncNow: () => {
      calls.push('sync-now');
    },
    setFilters: (next) => {
      calls.push(`set:${next.timeWindow}:${next.sourceDeviceId}`);
    },
    refresh: () => {
      calls.push('refresh');
    },
  });

  assert.deepEqual(calls, [
    'sync-now',
    'set:hour:device-123',
    'sync-now',
    'set:hour:device-123',
    'refresh',
  ]);
});

test('diagnostics refresh coordinator keeps only the latest in-flight request authoritative', () => {
  const coordinator = createDiagnosticsRefreshCoordinator();
  const firstRequestId = coordinator.beginRequest(false);
  const secondRequestId = coordinator.beginRequest(true);

  assert.equal(coordinator.isLatest(firstRequestId), false);
  assert.equal(coordinator.isLatest(secondRequestId), true);
  assert.equal(coordinator.releaseBusy(firstRequestId), true);
  assert.equal(coordinator.releaseBusy(secondRequestId), false);
});

test('diagnostics refresh coordinator clears busy state only for the latest visible refresh', () => {
  const coordinator = createDiagnosticsRefreshCoordinator();
  const firstVisibleRequestId = coordinator.beginRequest(false);
  const secondVisibleRequestId = coordinator.beginRequest(false);

  assert.equal(coordinator.releaseBusy(firstVisibleRequestId), false);
  assert.equal(coordinator.releaseBusy(secondVisibleRequestId), true);
});

test('silent diagnostics refreshes fail closed while a visible refresh is in flight', () => {
  const coordinator = createDiagnosticsRefreshCoordinator();
  const visibleRequestId = beginDiagnosticsRefreshRequest(coordinator, false);

  assert.equal(visibleRequestId, 1);
  assert.equal(coordinator.hasVisibleRequestInFlight(), true);
  assert.equal(beginDiagnosticsRefreshRequest(coordinator, true), null);
  assert.equal(coordinator.releaseBusy(visibleRequestId ?? -1), true);
  assert.equal(coordinator.hasVisibleRequestInFlight(), false);
  assert.equal(beginDiagnosticsRefreshRequest(coordinator, true), 2);
});

test('rolling diagnostics conflict-log query config keeps the cache key stable across live cutoff updates', () => {
  assert.deepEqual(
    buildConflictLogQueryConfig({
      timeWindow: 'hour',
      enabled: true,
    }),
    {
      queryKey: QUERY_KEYS.diagnosticsConflictLog('hour'),
      refetchOnWindowFocus: true,
      staleTime: STALE_DEFAULT,
      enabled: true,
    },
  );
  assert.deepEqual(buildConflictLogQueryConfig({
    timeWindow: 'hour',
    enabled: true,
  }).queryKey, QUERY_KEYS.diagnosticsConflictLog('hour'));
});

test('conflict-log refetch controller only refetches when an expanded rolling window boundary advances', () => {
  const controller = createDiagnosticsConflictLogRefetchController('2026-04-23T04:30:00.000Z');

  assert.equal(controller.shouldRefetch({
    expanded: false,
    sinceIso: '2026-04-23T04:30:00.000Z',
  }), false);
  assert.equal(controller.shouldRefetch({
    expanded: true,
    sinceIso: '2026-04-23T04:30:00.000Z',
  }), false);
  assert.equal(controller.shouldRefetch({
    expanded: true,
    sinceIso: '2026-04-23T04:30:00.000Z',
  }), false);
  assert.equal(controller.shouldRefetch({
    expanded: true,
    sinceIso: '2026-04-23T04:30:45.000Z',
  }), true);
  assert.equal(controller.shouldRefetch({
    expanded: false,
    sinceIso: '2026-04-23T04:30:45.000Z',
  }), false);
  assert.equal(controller.shouldRefetch({
    expanded: false,
    sinceIso: '2026-04-23T04:31:15.000Z',
  }), false);
  assert.equal(controller.shouldRefetch({
    expanded: true,
    sinceIso: '2026-04-23T04:31:15.000Z',
  }), true);
  assert.equal(controller.shouldRefetch({
    expanded: true,
    sinceIso: '2026-04-23T04:31:15.000Z',
  }), false);
});

test('conflict-log rendering hides cached rows whose fetched cutoff no longer matches the active rolling window', () => {
  assert.deepEqual(
    readDiagnosticsConflictLogEntries({
      sinceIso: '2026-04-23T04:30:00.000Z',
      entries: [{ id: 1 }],
    }, '2026-04-23T04:30:00.000Z'),
    [{ id: 1 }],
  );
  assert.deepEqual(
    readDiagnosticsConflictLogEntries({
      sinceIso: '2026-04-23T04:30:00.000Z',
      entries: [{ id: 1 }],
    }, '2026-04-23T04:31:15.000Z'),
    [],
  );
});

test('recent sync diagnostics rows respect the shared rolling time window and device scope filters', () => {
  const syncEvents = [
    {
      id: 'older',
      created_at: '2026-04-23T04:10:00.000Z',
      device_id: 'device-a',
    },
    {
      id: 'recent-other-device',
      created_at: '2026-04-23T04:40:00.000Z',
      device_id: 'device-b',
    },
    {
      id: 'recent-same-device',
      created_at: '2026-04-23T04:50:00.000Z',
      device_id: 'device-a',
    },
  ];

  assert.deepEqual(
    filterDiagnosticsRecentSyncEvents(syncEvents, {
      sinceIso: '2026-04-23T04:30:00.000Z',
      sourceDeviceId: null,
    }).map((entry) => entry.id),
    ['recent-other-device', 'recent-same-device'],
  );
  assert.deepEqual(
    filterDiagnosticsRecentSyncEvents(syncEvents, {
      sinceIso: '2026-04-23T04:30:00.000Z',
      sourceDeviceId: 'device-a',
    }).map((entry) => entry.id),
    ['recent-same-device'],
  );
  assert.deepEqual(
    filterDiagnosticsRecentSyncEvents(syncEvents, {
      sinceIso: null,
      sourceDeviceId: 'device-a',
    }).map((entry) => entry.id),
    ['older', 'recent-same-device'],
  );
});

test('recent logs expose retry actions only for quarantined unsynced outbox rows', () => {
  const recentLogs = buildRecentLogs({
    errorLogs: [],
    changelogEntries: [],
    recentSyncEvents: [
      {
        id: '11',
        entity_type: 'task',
        entity_id: 'task-1',
        operation: 'upsert',
        payload: '{}',
        created_at: '2026-04-23T05:00:00.000Z',
        device_id: 'dev-a',
        synced_at: null,
        retry_count: SYNC_OUTBOX_MAX_RETRIES,
        last_retry_at: '2026-04-23T05:01:00.000Z',
      },
      {
        id: '12',
        entity_type: 'task',
        entity_id: 'task-2',
        operation: 'upsert',
        payload: '{}',
        created_at: '2026-04-23T04:59:00.000Z',
        device_id: 'dev-a',
        synced_at: '2026-04-23T05:02:00.000Z',
        retry_count: SYNC_OUTBOX_MAX_RETRIES,
        last_retry_at: '2026-04-23T05:01:00.000Z',
      },
      {
        id: '13',
        entity_type: 'list',
        entity_id: 'list-1',
        operation: 'delete',
        payload: '{}',
        created_at: '2026-04-23T04:58:00.000Z',
        device_id: 'dev-a',
        synced_at: null,
        retry_count: SYNC_OUTBOX_MAX_RETRIES - 1,
        last_retry_at: null,
      },
    ],
  });

  assert.deepEqual(
    recentLogs.map((entry) => [entry.id, entry.retryOutboxEntryId]),
    [
      ['sync:11', '11'],
      ['sync:12', null],
      ['sync:13', null],
    ],
  );
});

test('filtered recent sync loader widens the fetch window until matching rows fill the diagnostics slice', async () => {
  const calls: number[] = [];
  const matchingRows = [
    {
      id: 'match-1',
      created_at: '2026-04-23T04:50:00.000Z',
      device_id: 'device-a',
    },
    {
      id: 'match-2',
      created_at: '2026-04-23T04:40:00.000Z',
      device_id: 'device-a',
    },
  ];
  const fillerRows = Array.from({ length: 238 }, (_, index) => ({
    id: `filler-${index}`,
    created_at: `2026-04-23T05:${String(59 - (index % 60)).padStart(2, '0')}:00.000Z`,
    device_id: 'device-b',
  }));

  const filtered = await loadFilteredRecentSyncEvents({
    fetchRecentOutboxEntries: async (limit) => {
      calls.push(limit);
      if (limit <= 120) {
        return fillerRows.slice(0, 120);
      }
      return [...fillerRows, ...matchingRows];
    },
    filters: {
      sinceIso: '2026-04-23T04:30:00.000Z',
      sourceDeviceId: 'device-a',
    },
    targetCount: 2,
    initialLimit: 120,
  });

  assert.deepEqual(calls, [120, 240]);
  assert.deepEqual(filtered.map((entry) => entry.id), ['match-1', 'match-2']);
});

test('device-scoped diagnostics fail closed for local error logs that cannot be attributed to a device id', () => {
  assert.equal(shouldIncludeDiagnosticsErrorLogs(null), true);
  assert.equal(shouldIncludeDiagnosticsErrorLogs('device-a'), false);
});

test('error-log IPC wrapper does not expose the ignored source-device filter', () => {
  const source = readFileSync(join(ROOT, 'app/src/lib/ipc/settings.ts'), 'utf8');
  const getErrorLogsSource = source.match(/export const getErrorLogs[\s\S]*?export const clearErrorLogs/)?.[0] ?? '';
  assert.ok(getErrorLogsSource, 'settings IPC should export getErrorLogs');
  assert.doesNotMatch(
    getErrorLogsSource,
    /sourceDeviceId|source_device_id/,
    'getErrorLogs should not expose or forward source-device filters until error_logs can honor them',
  );
});

test('diagnostics query builders keep key heads and cache timing aligned to the shared contract', () => {
  assert.deepEqual(buildDiagnosticsDeviceIdsQueryConfig(), {
    queryKey: QUERY_KEYS.diagnosticsDeviceIds(),
    refetchOnWindowFocus: true,
    staleTime: STALE_LONG,
  });

  assert.deepEqual(
    buildConflictLogQueryConfig({
      timeWindow: 'day',
      enabled: true,
    }),
    {
      queryKey: QUERY_KEYS.diagnosticsConflictLog('day'),
      refetchOnWindowFocus: true,
      staleTime: STALE_DEFAULT,
      enabled: true,
    },
  );
});
