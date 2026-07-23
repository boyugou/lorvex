import { useEffect, useMemo, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { getCalendarEventsUnified } from '@/lib/ipc/calendar';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { STALE_LONG } from '@/lib/query/timing';
import { getRelativeDateYmd, useConfiguredTimezone } from '@/lib/dayContext';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';

interface UseTaskDetailEventLinkSearchArgs {
  excludeIds: string[];
}

interface ProviderEventLinkIdentity {
  provider_kind: string;
  provider_scope: string;
  provider_event_key: string;
}

export function buildTaskDetailProviderEventUnifiedId(link: ProviderEventLinkIdentity): string {
  return `${link.provider_kind}:${link.provider_scope}:${link.provider_event_key}`;
}

export function buildTaskDetailEventLinkSearchResults(
  events: UnifiedCalendarEvent[],
  excludeIds: string[],
  query: string,
): UnifiedCalendarEvent[] {
  const normalizedQuery = query.toLowerCase().trim();
  const excluded = new Set(excludeIds);
  return events
    .filter((event) => !excluded.has(event.id))
    .filter((event) => !normalizedQuery || event.title.toLowerCase().includes(normalizedQuery))
    .slice(0, 8);
}

export function useTaskDetailEventLinkSearch({
  excludeIds,
}: UseTaskDetailEventLinkSearchArgs) {
  const [query, setQuery] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);
  const { timezone } = useConfiguredTimezone();

  useEffect(() => {
    inputRef.current?.focus();
  }, []);

  // Compute the ±7/+30 day window in the user's configured timezone.
  // `getRelativeDateYmd` routes through `Intl.DateTimeFormat` +
  // UTC-safe YMD arithmetic so the boundary is stable across
  // timezones and DST transitions. Mixing local-time
  // `Date.setDate(getDate() ± N)` arithmetic with a UTC-date
  // `toISOString().slice(0, 10)` extraction would drift the window
  // by ±1 day for users in timezones far from UTC depending on
  // wall-clock time of opening, hiding events near the boundary.
  const from = useMemo(() => getRelativeDateYmd(timezone, -7), [timezone]);
  const to = useMemo(() => getRelativeDateYmd(timezone, 30), [timezone]);

  const { data: events = [] } = useQuery({
    queryKey: QUERY_KEYS.eventsUnifiedForLinkSearch(from, to),
    queryFn: ({ signal }) => getCalendarEventsUnified(from, to, signal),
    staleTime: STALE_LONG,
  });

  const results = useMemo(() => {
    return buildTaskDetailEventLinkSearchResults(events, excludeIds, query);
  }, [events, excludeIds, query]);

  return {
    inputRef,
    query,
    results,
    setQuery,
  };
}
