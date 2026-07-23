import type { QueryClient } from '@tanstack/react-query';
import { describe, expect, it } from 'vitest';

import { QK } from '@/lib/query/queryKeys';
import {
  clearNativeCalendarPanelProviderEvents,
  invalidateNativeCalendarPanelMutationQueries,
  syncNativeCalendarPanelNow,
} from './useNativeCalendarPanelController.logic';

function collectInvalidatedHeads(queryClientCall: unknown): string[] {
  const args = queryClientCall as {
    predicate?: (query: { queryKey: readonly unknown[] }) => boolean;
    queryKey?: readonly unknown[];
  };

  if (args.predicate) {
    return Object.values(QK).filter((head) => args.predicate?.({ queryKey: [head] }));
  }
  if (args.queryKey && typeof args.queryKey[0] === 'string') {
    return [args.queryKey[0]];
  }
  return [];
}

describe('native calendar panel invalidation', () => {
  it('invalidates every calendar mutation query family after native sync or clear', () => {
    const invalidateCalls: unknown[] = [];
    const queryClient = {
      invalidateQueries: (args: unknown) => {
        invalidateCalls.push(args);
      },
    } as unknown as QueryClient;

    invalidateNativeCalendarPanelMutationQueries(queryClient);

    const invalidatedHeads = invalidateCalls.flatMap(collectInvalidatedHeads);
    expect(invalidatedHeads).toEqual(
      expect.arrayContaining([
        QK.calendarEvents,
        QK.calendarEvent,
        QK.todayEvents,
        QK.dailyReviewEvents,
        QK.upcomingEvents,
        QK.calendarTasks,
        QK.weeklyReview,
        QK.weeklyReviewEvents,
        QK.taskEventLinks,
        QK.taskProviderEventLinks,
        QK.eventsUnifiedForLinkSearch,
      ]),
    );
  });

  it('invalidates the full calendar mutation set after successful native sync', async () => {
    const invalidateCalls: unknown[] = [];
    const queryClient = {
      invalidateQueries: (args: unknown) => {
        invalidateCalls.push(args);
      },
    } as unknown as QueryClient;
    const lastResults: unknown[] = [];
    const toastMessages: string[] = [];

    await syncNativeCalendarPanelNow({
      queryClient,
      setLastResult: (result) => lastResults.push(result),
      syncNow: async () => ({
        available: true,
        error: null,
        events_imported: 1,
        events_removed: 0,
        events_updated: 0,
      }),
      t: (key) => key,
      format: (key, vars) => `${key}:${JSON.stringify(vars)}`,
      toast: {
        errorWithDetail: () => undefined,
        success: (message) => toastMessages.push(message),
      },
    });

    expect(lastResults).toHaveLength(1);
    expect(toastMessages).toHaveLength(1);
    expect(invalidateCalls.flatMap(collectInvalidatedHeads)).toEqual(
      expect.arrayContaining([QK.calendarEvents, QK.taskEventLinks, QK.weeklyReviewEvents]),
    );
  });

  it('invalidates the full calendar mutation set after native clear succeeds', async () => {
    const invalidateCalls: unknown[] = [];
    const queryClient = {
      invalidateQueries: (args: unknown) => {
        invalidateCalls.push(args);
      },
    } as unknown as QueryClient;

    await clearNativeCalendarPanelProviderEvents({
      clearNativeCalendarEvents: async (source) => {
        expect(source).toBe('windows_appointments');
        return { deleted: 2 };
      },
      clearProviderKind: 'windows_appointments',
      queryClient,
      t: (key) => key,
      format: (key, vars) => `${key}:${JSON.stringify(vars)}`,
      toast: {
        errorWithDetail: () => undefined,
        success: () => undefined,
      },
    });

    expect(invalidateCalls.flatMap(collectInvalidatedHeads)).toEqual(
      expect.arrayContaining([QK.calendarEvents, QK.taskEventLinks, QK.weeklyReviewEvents]),
    );
  });
});
