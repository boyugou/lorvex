import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { STALE_DEFAULT, STALE_LONG } from '@/lib/query/timing';
import { DAY_MS, HOUR_MS, WEEK_MS } from '@/lib/time/durations';

export type DiagnosticsTimeWindowPreset = 'hour' | 'day' | 'week' | 'all';
export interface DiagnosticsFilters {
  timeWindow: DiagnosticsTimeWindowPreset;
  sourceDeviceId: string | null;
}

export const DEFAULT_DIAGNOSTICS_TIME_WINDOW: DiagnosticsTimeWindowPreset = 'day';
export const DEFAULT_DIAGNOSTICS_FILTERS: DiagnosticsFilters = {
  timeWindow: DEFAULT_DIAGNOSTICS_TIME_WINDOW,
  sourceDeviceId: null,
};

export function buildDiagnosticsRawFilters(args: {
  timeWindow: DiagnosticsTimeWindowPreset;
  sourceDeviceId: string | null;
}): DiagnosticsFilters {
  return {
    ...DEFAULT_DIAGNOSTICS_FILTERS,
    timeWindow: args.timeWindow,
    sourceDeviceId: args.sourceDeviceId,
  };
}

interface DiagnosticsFilterIntentController {
  getFilters: () => DiagnosticsFilters;
  setFilters: (next: DiagnosticsFilters) => void;
  resolve: (nowMs: number) => { sinceIso: string | null; sourceDeviceId: string | null };
}

interface DiagnosticsRefreshCoordinator {
  beginRequest: (silent: boolean) => number;
  hasVisibleRequestInFlight: () => boolean;
  isLatest: (requestId: number) => boolean;
  releaseBusy: (requestId: number) => boolean;
}

interface DiagnosticsConflictLogRefetchController {
  shouldRefetch: (args: {
    expanded: boolean;
    sinceIso: string | null;
    sourceDeviceId: string | null;
  }) => boolean;
}

interface DiagnosticsPanelFilterEffectController {
  apply: (args: {
    filters: DiagnosticsFilters;
    syncNow: () => void;
    setFilters: (filters: DiagnosticsFilters) => void;
    refresh: () => void;
  }) => void;
}

interface DiagnosticsRecentSyncEventLike {
  created_at: string;
  device_id: string;
}

interface DiagnosticsConflictLogQueryData<T> {
  sinceIso: string | null;
  sourceDeviceId: string | null;
  entries: readonly T[];
}

interface LoadFilteredRecentSyncEventsArgs<T extends DiagnosticsRecentSyncEventLike> {
  fetchRecentOutboxEntries: (limit: number) => Promise<readonly T[]>;
  filters: { sinceIso: string | null; sourceDeviceId: string | null };
  targetCount?: number;
  initialLimit?: number;
}

export function createDiagnosticsFilterIntentController(
  initial: DiagnosticsFilters = DEFAULT_DIAGNOSTICS_FILTERS,
): DiagnosticsFilterIntentController {
  let filters = initial;
  return {
    getFilters: () => filters,
    setFilters: (next) => {
      filters = next;
    },
    resolve: (nowMs) => resolveDiagnosticsFilters(filters, nowMs),
  };
}

export function createDiagnosticsRefreshCoordinator(): DiagnosticsRefreshCoordinator {
  let latestRequestId = 0;
  let busyRequestId: number | null = null;
  return {
    beginRequest: (silent) => {
      latestRequestId += 1;
      if (!silent) {
        busyRequestId = latestRequestId;
      }
      return latestRequestId;
    },
    hasVisibleRequestInFlight: () => busyRequestId !== null,
    isLatest: (requestId) => requestId === latestRequestId,
    releaseBusy: (requestId) => {
      if (busyRequestId !== requestId) {
        return false;
      }
      busyRequestId = null;
      return true;
    },
  };
}

export function beginDiagnosticsRefreshRequest(
  coordinator: DiagnosticsRefreshCoordinator,
  silent: boolean,
): number | null {
  if (silent && coordinator.hasVisibleRequestInFlight()) {
    return null;
  }
  return coordinator.beginRequest(silent);
}

export function createDiagnosticsConflictLogRefetchController(
  initialSinceIso: string | null,
  initialSourceDeviceId: string | null,
): DiagnosticsConflictLogRefetchController {
  let wasExpanded = false;
  let lastExpandedFilters = {
    sinceIso: initialSinceIso,
    sourceDeviceId: initialSourceDeviceId,
  };

  return {
    shouldRefetch: ({ expanded, sinceIso, sourceDeviceId }) => {
      const nextFilters = { sinceIso, sourceDeviceId };
      if (!expanded) {
        wasExpanded = false;
        return false;
      }
      if (!wasExpanded) {
        const shouldRefetch =
          lastExpandedFilters.sinceIso !== sinceIso ||
          lastExpandedFilters.sourceDeviceId !== sourceDeviceId;
        wasExpanded = true;
        lastExpandedFilters = nextFilters;
        return shouldRefetch;
      }
      if (
        lastExpandedFilters.sinceIso === sinceIso &&
        lastExpandedFilters.sourceDeviceId === sourceDeviceId
      ) {
        return false;
      }
      lastExpandedFilters = nextFilters;
      return true;
    },
  };
}

export function createDiagnosticsPanelFilterEffectController(): DiagnosticsPanelFilterEffectController {
  let didMount = false;

  return {
    apply: ({ filters, syncNow, setFilters, refresh }) => {
      syncNow();
      setFilters(filters);
      if (didMount) {
        refresh();
        return;
      }
      didMount = true;
    },
  };
}

export function readDiagnosticsConflictLogEntries<T>(
  data: DiagnosticsConflictLogQueryData<T> | undefined,
  sinceIso: string | null,
  sourceDeviceId: string | null,
): readonly T[] {
  if (!data || data.sinceIso !== sinceIso || data.sourceDeviceId !== sourceDeviceId) {
    return [];
  }
  return data.entries;
}

export function resolveDiagnosticsSinceIso(
  preset: DiagnosticsTimeWindowPreset,
  nowMs: number,
): string | null {
  if (preset === 'all') return null;
  const deltaMs = preset === 'hour'
    ? HOUR_MS
    : preset === 'day'
      ? DAY_MS
      : WEEK_MS;
  return new Date(nowMs - deltaMs).toISOString();
}

export function resolveDiagnosticsFilters(
  filters: DiagnosticsFilters,
  nowMs: number,
): { sinceIso: string | null; sourceDeviceId: string | null } {
  return {
    sinceIso: resolveDiagnosticsSinceIso(filters.timeWindow, nowMs),
    sourceDeviceId: filters.sourceDeviceId,
  };
}

export function filterDiagnosticsRecentSyncEvents<T extends DiagnosticsRecentSyncEventLike>(
  events: readonly T[],
  filters: { sinceIso: string | null; sourceDeviceId: string | null },
): T[] {
  return events.filter((event) => {
    if (filters.sourceDeviceId && event.device_id !== filters.sourceDeviceId) {
      return false;
    }
    if (filters.sinceIso === null) {
      return true;
    }
    if (!event.created_at) {
      return false;
    }
    return event.created_at >= filters.sinceIso;
  });
}

export function shouldIncludeDiagnosticsErrorLogs(sourceDeviceId: string | null): boolean {
  return sourceDeviceId === null;
}

export async function loadFilteredRecentSyncEvents<T extends DiagnosticsRecentSyncEventLike>(
  args: LoadFilteredRecentSyncEventsArgs<T>,
): Promise<T[]> {
  const targetCount = args.targetCount ?? 120;
  let limit = Math.max(args.initialLimit ?? targetCount, targetCount);

  for (;;) {
    const events = await args.fetchRecentOutboxEntries(limit);
    const filtered = filterDiagnosticsRecentSyncEvents(events, args.filters);
    if (filtered.length >= targetCount || events.length < limit) {
      return filtered.slice(0, targetCount);
    }
    limit *= 2;
  }
}

export function buildDiagnosticsDeviceIdsQueryConfig() {
  return {
    queryKey: QUERY_KEYS.diagnosticsDeviceIds(),
    refetchOnWindowFocus: true as const,
    staleTime: STALE_LONG,
  };
}

export function buildConflictLogQueryConfig(args: {
  timeWindow: DiagnosticsTimeWindowPreset;
  sourceDeviceId: string | null;
  enabled: boolean;
}) {
  return {
    queryKey: QUERY_KEYS.diagnosticsConflictLog(args.timeWindow, args.sourceDeviceId),
    refetchOnWindowFocus: true as const,
    staleTime: STALE_DEFAULT,
    enabled: args.enabled,
  };
}
