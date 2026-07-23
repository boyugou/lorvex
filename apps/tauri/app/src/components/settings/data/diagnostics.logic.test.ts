import { describe, expect, it } from 'vitest';
import {
  createDiagnosticsConflictLogRefetchController,
  filterDiagnosticsRecentSyncEvents,
  loadFilteredRecentSyncEvents,
  readDiagnosticsConflictLogEntries,
} from './diagnostics.logic';

describe('diagnostics conflict log filters', () => {
  it('invalidates expanded conflict-log data when device scope changes', () => {
    const controller = createDiagnosticsConflictLogRefetchController(null, null);

    expect(controller.shouldRefetch({
      expanded: true,
      sinceIso: null,
      sourceDeviceId: null,
    })).toBe(false);
    expect(controller.shouldRefetch({
      expanded: true,
      sinceIso: null,
      sourceDeviceId: 'device-a',
    })).toBe(true);
    expect(controller.shouldRefetch({
      expanded: true,
      sinceIso: null,
      sourceDeviceId: 'device-a',
    })).toBe(false);
  });

  it('drops stale conflict-log query data for mismatched device scope', () => {
    const entries = [{ id: 1 }];

    expect(readDiagnosticsConflictLogEntries({
      sinceIso: null,
      sourceDeviceId: 'device-a',
      entries,
    }, null, 'device-b')).toEqual([]);
    expect(readDiagnosticsConflictLogEntries({
      sinceIso: null,
      sourceDeviceId: 'device-a',
      entries,
    }, null, 'device-a')).toEqual(entries);
  });
});

describe('diagnostics recent sync event filters', () => {
  const events = [
    { id: 'old-a', created_at: '2026-04-01T00:00:00.000Z', device_id: 'device-a' },
    { id: 'fresh-a', created_at: '2026-04-03T00:00:00.000Z', device_id: 'device-a' },
    { id: 'fresh-b', created_at: '2026-04-04T00:00:00.000Z', device_id: 'device-b' },
    { id: 'missing-time', created_at: '', device_id: 'device-a' },
  ];

  it('combines device and since filters without widening the result set', () => {
    expect(filterDiagnosticsRecentSyncEvents(events, {
      sinceIso: '2026-04-02T00:00:00.000Z',
      sourceDeviceId: 'device-a',
    }).map((event) => event.id)).toEqual(['fresh-a']);
  });

  it('keeps empty timestamps only when the time window is unbounded', () => {
    expect(filterDiagnosticsRecentSyncEvents(events, {
      sinceIso: null,
      sourceDeviceId: 'device-a',
    }).map((event) => event.id)).toEqual(['old-a', 'fresh-a', 'missing-time']);

    expect(filterDiagnosticsRecentSyncEvents(events, {
      sinceIso: '2026-04-01T00:00:00.000Z',
      sourceDeviceId: 'device-a',
    }).map((event) => event.id)).toEqual(['old-a', 'fresh-a']);
  });

  it('doubles the fetch limit until enough filtered rows are available', async () => {
    const requestedLimits: number[] = [];
    const fetched = await loadFilteredRecentSyncEvents({
      targetCount: 2,
      initialLimit: 2,
      filters: {
        sinceIso: null,
        sourceDeviceId: 'device-a',
      },
      fetchRecentOutboxEntries: async (limit) => {
        requestedLimits.push(limit);
        return [
          { id: 'skip-b', created_at: '2026-04-04T00:00:00.000Z', device_id: 'device-b' },
          { id: 'keep-a1', created_at: '2026-04-03T00:00:00.000Z', device_id: 'device-a' },
          { id: 'keep-a2', created_at: '2026-04-02T00:00:00.000Z', device_id: 'device-a' },
          { id: 'keep-a3', created_at: '2026-04-01T00:00:00.000Z', device_id: 'device-a' },
        ].slice(0, limit);
      },
    });

    expect(requestedLimits).toEqual([2, 4]);
    expect(fetched.map((event) => event.id)).toEqual(['keep-a1', 'keep-a2']);
  });

  it('stops fetching when the backend returns fewer rows than requested', async () => {
    const requestedLimits: number[] = [];
    const fetched = await loadFilteredRecentSyncEvents({
      targetCount: 3,
      initialLimit: 3,
      filters: {
        sinceIso: null,
        sourceDeviceId: 'device-a',
      },
      fetchRecentOutboxEntries: async (limit) => {
        requestedLimits.push(limit);
        return [
          { id: 'skip-b', created_at: '2026-04-04T00:00:00.000Z', device_id: 'device-b' },
          { id: 'keep-a', created_at: '2026-04-03T00:00:00.000Z', device_id: 'device-a' },
        ];
      },
    });

    expect(requestedLimits).toEqual([3]);
    expect(fetched.map((event) => event.id)).toEqual(['keep-a']);
  });
});
