import { useMemo, useRef } from 'react';
import { useQueries, useQuery } from '@tanstack/react-query';
import { getCalendarEvent, getLinkedEventsForTask, getProviderEventLinksForTask } from '@/lib/ipc/calendar';
import type { CalendarEvent } from '@/lib/ipc/calendar';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { STALE_LONG } from '@/lib/query/timing';

export function useTaskDetailEventLinkQueries(taskId: string) {
  const { data: links = [] } = useQuery({
    queryKey: QUERY_KEYS.taskEventLinks(taskId),
    queryFn: ({ signal }) => getLinkedEventsForTask(taskId, signal),
    staleTime: STALE_LONG,
    gcTime: 30_000,
  });

  const eventIds = useMemo(() => links.map((link) => link.calendar_event_id), [links]);

  const eventQueries = useQueries({
    queries: eventIds.map((id) => ({
      queryKey: QUERY_KEYS.calendarEvent(id),
      queryFn: ({ signal }: { signal?: AbortSignal }) => getCalendarEvent(id, signal),
      staleTime: STALE_LONG,
      gcTime: 30_000,
    })),
  });

  // Stabilize eventMap: useQueries returns a new array reference every render,
  // so we compare the actual data values to avoid unnecessary re-renders.
  const eventMapRef = useRef<Record<string, CalendarEvent>>({});
  const nextEventMap: Record<string, CalendarEvent> = {};
  for (let index = 0; index < eventIds.length; index += 1) {
    const event = eventQueries[index]?.data;
    const eventId = eventIds[index];
    if (event && eventId) {
      nextEventMap[eventId] = event;
    }
  }
  // Shallow-compare: same keys and same object references for each value
  const prevMap = eventMapRef.current;
  const prevKeys = Object.keys(prevMap);
  const nextKeys = Object.keys(nextEventMap);
  const isEqual = prevKeys.length === nextKeys.length
    && nextKeys.every((key) => prevMap[key] === nextEventMap[key]);
  if (!isEqual) {
    eventMapRef.current = nextEventMap;
  }
  const eventMap = eventMapRef.current;

  const { data: providerLinks = [] } = useQuery({
    queryKey: QUERY_KEYS.taskProviderEventLinks(taskId),
    queryFn: ({ signal }) => getProviderEventLinksForTask(taskId, signal),
    staleTime: STALE_LONG,
    gcTime: 30_000,
  });

  return {
    eventIds,
    eventMap,
    links,
    providerLinks,
  };
}
