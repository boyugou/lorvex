import { describe, expect, it } from 'vitest';
import { SYNC_ENTITY_TYPES } from '@lorvex/shared/types';

import {
  QK,
  QUERY_KEYS,
  QUERY_ENTITY_INVALIDATION_MAP,
  QUERY_INVALIDATION_REGISTRY,
  QUERY_KEY_HEADS,
  queryKeyHeadsForInvalidationIntent,
} from './queryKeys';
import { DEV_FOCUS_SESSION_TRIED } from '../preferences/keys';

describe('query key registry', () => {
  const knownHeads = new Set<string>(QUERY_KEY_HEADS);
  const expectEntityCovers = (entity: string, heads: readonly string[]) => {
    expect(QUERY_ENTITY_INVALIDATION_MAP[entity]).toEqual(
      expect.arrayContaining([...heads]),
    );
  };

  it('keeps QK values unique and registered', () => {
    expect(QUERY_KEY_HEADS).toHaveLength(Object.keys(QK).length);
    expect(new Set(QUERY_KEY_HEADS).size).toBe(QUERY_KEY_HEADS.length);
  });

  it('keeps every invalidation intent non-empty, deduped, and bound to known heads', () => {
    for (const [intent, heads] of Object.entries(QUERY_INVALIDATION_REGISTRY)) {
      expect(heads.length, `${intent} should invalidate at least one head`).toBeGreaterThan(0);
      expect(new Set(heads).size, `${intent} should not carry duplicate heads`).toBe(heads.length);
      for (const head of heads) {
        expect(knownHeads.has(head), `${intent} references unknown query head ${head}`).toBe(true);
      }
    }
  });

  it('keeps every entity invalidation non-empty, deduped, and bound to known heads', () => {
    for (const [entity, heads] of Object.entries(QUERY_ENTITY_INVALIDATION_MAP)) {
      expect(heads.length, `${entity} should invalidate at least one head`).toBeGreaterThan(0);
      expect(new Set(heads).size, `${entity} should not carry duplicate heads`).toBe(heads.length);
      for (const head of heads) {
        expect(knownHeads.has(head), `${entity} references unknown query head ${head}`).toBe(true);
      }
    }
  });

  it('covers every canonical sync entity with an explicit invalidation map entry', () => {
    expect(Object.keys(QUERY_ENTITY_INVALIDATION_MAP).sort()).toEqual(
      expect.arrayContaining([...SYNC_ENTITY_TYPES].sort()),
    );
  });

  it('keeps bootstrap invalidated with the today surface', () => {
    expect(queryKeyHeadsForInvalidationIntent('today.surface')).toContain(QK.todayBootstrap);
  });

  it('keeps preference entity changes aligned with setup and dashboard projections', () => {
    expect(QUERY_ENTITY_INVALIDATION_MAP.preference).toEqual(
      expect.arrayContaining([QK.preference, QK.dashboardLayout, QK.setupStatus]),
    );
  });

  it('keeps every query key factory shape explicit and canonical', () => {
    const factoryCases: Array<[keyof typeof QUERY_KEYS, readonly unknown[], readonly unknown[]]> = [
      ['head', QUERY_KEYS.head(QK.overview), [QK.overview]],
      ['overview', QUERY_KEYS.overview(), [QK.overview]],
      ['lists', QUERY_KEYS.lists(), [QK.lists]],
      ['list', QUERY_KEYS.list('list-1'), [QK.list, 'list-1']],
      ['preference', QUERY_KEYS.preference('pref-1'), [QK.preference, 'pref-1']],
      ['preferenceRoot', QUERY_KEYS.preferenceRoot(), [QK.preference]],
      ['currentFocus', QUERY_KEYS.currentFocus(), [QK.currentFocus]],
      ['focusSchedule', QUERY_KEYS.focusSchedule(), [QK.focusSchedule]],
      ['allTasks', QUERY_KEYS.allTasks(true, false), [QK.allTasks, true, false]],
      ['task', QUERY_KEYS.task('task-1'), [QK.task, 'task-1']],
      ['taskAttribution', QUERY_KEYS.taskAttribution('task-1'), [QK.taskAttribution, 'task-1']],
      ['tasksBlockedBy', QUERY_KEYS.tasksBlockedBy('task-1'), [QK.tasksBlockedBy, 'task-1']],
      ['taskEventLinks', QUERY_KEYS.taskEventLinks('task-1'), [QK.taskEventLinks, 'task-1']],
      ['taskProviderEventLinks', QUERY_KEYS.taskProviderEventLinks('task-1'), [QK.taskProviderEventLinks, 'task-1']],
      ['taskReminders', QUERY_KEYS.taskReminders('task-1'), [QK.taskReminders, 'task-1']],
      ['calendarEvent', QUERY_KEYS.calendarEvent('event-1'), [QK.calendarEvent, 'event-1']],
      ['calendarEvents', QUERY_KEYS.calendarEvents('2026-05-01', '2026-05-31'), [QK.calendarEvents, '2026-05-01', '2026-05-31']],
      ['calendarTasks', QUERY_KEYS.calendarTasks('2026-05-01', '2026-05-31'), [QK.calendarTasks, '2026-05-01', '2026-05-31']],
      ['calendarSubscriptions', QUERY_KEYS.calendarSubscriptions(), [QK.calendarSubscriptions]],
      ['todayEvents', QUERY_KEYS.todayEvents('2026-05-01'), [QK.todayEvents, '2026-05-01']],
      ['todayPoolTasks', QUERY_KEYS.todayPoolTasks(), [QK.todayPoolTasks]],
      ['todayOverdueTasks', QUERY_KEYS.todayOverdueTasks(), [QK.todayOverdueTasks]],
      ['somedayTasks', QUERY_KEYS.somedayTasks(), [QK.somedayTasks]],
      ['recurringTasks', QUERY_KEYS.recurringTasks(), [QK.recurringTasks]],
      ['upcomingTasks', QUERY_KEYS.upcomingTasks('2026-05-01', 7), [QK.upcomingTasks, '2026-05-01', 7]],
      ['upcomingEvents', QUERY_KEYS.upcomingEvents('2026-05-01', '2026-05-08'), [QK.upcomingEvents, '2026-05-01', '2026-05-08']],
      ['upcomingWeekTasks', QUERY_KEYS.upcomingWeekTasks('2026-05-01', 7), [QK.upcomingWeekTasks, '2026-05-01', 7]],
      ['search', QUERY_KEYS.search('focus'), [QK.search, 'focus']],
      ['weeklyReview', QUERY_KEYS.weeklyReview('2026-05-01'), [QK.weeklyReview, '2026-05-01']],
      ['weeklyReviewUpcoming', QUERY_KEYS.weeklyReviewUpcoming('2026-05-04', '2026-05-10'), [QK.weeklyReviewUpcoming, '2026-05-04', '2026-05-10']],
      ['weeklyReviewEvents', QUERY_KEYS.weeklyReviewEvents('2026-05-04', '2026-05-10'), [QK.weeklyReviewEvents, '2026-05-04', '2026-05-10']],
      ['weeklyReviewHabits', QUERY_KEYS.weeklyReviewHabits('2026-05-01'), [QK.weeklyReviewHabits, '2026-05-01']],
      ['dailyReviews', QUERY_KEYS.dailyReviews(), [QK.dailyReviews]],
      ['dailyReview', QUERY_KEYS.dailyReview('2026-05-01'), [QK.dailyReview, '2026-05-01']],
      ['dailyReviewEvents', QUERY_KEYS.dailyReviewEvents('2026-05-01'), [QK.dailyReviewEvents, '2026-05-01']],
      ['todaysHabits', QUERY_KEYS.todaysHabits('2026-05-01'), [QK.todaysHabits, '2026-05-01']],
      ['habitsWithStats', QUERY_KEYS.habitsWithStats('2026-05-01'), [QK.habitsWithStats, '2026-05-01']],
      ['habitReminderPolicies', QUERY_KEYS.habitReminderPolicies(), [QK.habitReminderPolicies]],
      ['aiMemory', QUERY_KEYS.aiMemory(), [QK.aiMemory]],
      ['aiChangelog', QUERY_KEYS.aiChangelog(50), [QK.aiChangelog, 50]],
      ['taskAiChangelog', QUERY_KEYS.taskAiChangelog('task-1', 50), [QK.aiChangelog, 'task', 'task-1', 50]],
      ['memoryHistory', QUERY_KEYS.memoryHistory('memory-key'), [QK.memoryHistory, 'memory-key']],
      ['deviceState', QUERY_KEYS.deviceState(DEV_FOCUS_SESSION_TRIED), [QK.deviceState, DEV_FOCUS_SESSION_TRIED]],
      ['unseenErrorLogCount', QUERY_KEYS.unseenErrorLogCount(), [QK.unseenErrorLogCount]],
      ['setupStatus', QUERY_KEYS.setupStatus(), [QK.setupStatus]],
      ['dashboardLayout', QUERY_KEYS.dashboardLayout(), [QK.dashboardLayout]],
      ['eventsUnifiedForLinkSearch', QUERY_KEYS.eventsUnifiedForLinkSearch('2026-05-01', '2026-05-31'), [QK.eventsUnifiedForLinkSearch, '2026-05-01', '2026-05-31']],
      ['allTags', QUERY_KEYS.allTags(), [QK.allTags]],
      ['todayBootstrap', QUERY_KEYS.todayBootstrap(), [QK.todayBootstrap]],
      ['savedQueries', QUERY_KEYS.savedQueries('all_tasks'), [QK.savedQueries, 'all_tasks']],
      ['mcpServerStatus', QUERY_KEYS.mcpServerStatus(), [QK.mcpServerStatus]],
      ['syncStatus', QUERY_KEYS.syncStatus('device_id'), [QK.syncStatus, 'device_id']],
      ['diagnosticsDeviceIds', QUERY_KEYS.diagnosticsDeviceIds(), [QK.diagnostics, 'device-ids']],
      ['diagnosticsConflictLog', QUERY_KEYS.diagnosticsConflictLog('day', null), [QK.diagnostics, 'conflict-log', 'day', 'all-devices']],
      ['appVersion', QUERY_KEYS.appVersion(), [QK.appVersion]],
    ];

    expect(factoryCases.map(([name]) => name).sort()).toEqual(Object.keys(QUERY_KEYS).sort());
    for (const [name, actual, expected] of factoryCases) {
      expect(actual, name).toEqual(expected);
      expect(knownHeads.has(String(actual[0])), `${name} references an unknown head`).toBe(true);
    }
    expect(QUERY_KEYS.weeklyReview()).toEqual([QK.weeklyReview]);
    expect(QUERY_KEYS.weeklyReviewUpcoming()).toEqual([QK.weeklyReviewUpcoming]);
    expect(QUERY_KEYS.aiChangelog()).toEqual([QK.aiChangelog]);
    expect(QUERY_KEYS.memoryHistory()).toEqual([QK.memoryHistory]);
    expect(QUERY_KEYS.savedQueries()).toEqual([QK.savedQueries]);
  });

  it('keeps task tag changes aligned with every task-card surface that renders tags', () => {
    expectEntityCovers('task_tag', [
      QK.todayBootstrap,
      QK.todayPoolTasks,
      QK.todayOverdueTasks,
      QK.allTasks,
      QK.list,
      QK.task,
      QK.search,
      QK.allTags,
      QK.weeklyReviewUpcoming,
    ]);
  });

  it('keeps tag changes aligned with task-card surfaces, tag metadata, and search', () => {
    expectEntityCovers('tag', [
      QK.todayBootstrap,
      QK.todayPoolTasks,
      QK.todayOverdueTasks,
      QK.allTasks,
      QK.list,
      QK.task,
      QK.search,
      QK.allTags,
      QK.weeklyReviewUpcoming,
    ]);
  });

  it('keeps task reminder changes aligned with task detail and today reminder surfaces', () => {
    expectEntityCovers('task_reminder', [
      QK.taskReminders,
      QK.todayBootstrap,
      QK.todayPoolTasks,
      QK.todayOverdueTasks,
    ]);
  });

  it('keeps calendar event changes aligned with today, daily review, weekly review, and task-link surfaces', () => {
    expectEntityCovers('calendar_event', [
      QK.calendarEvents,
      QK.calendarEvent,
      QK.todayEvents,
      QK.dailyReviewEvents,
      QK.weeklyReviewEvents,
      QK.taskEventLinks,
      QK.taskProviderEventLinks,
      QK.eventsUnifiedForLinkSearch,
    ]);
    expect(QUERY_ENTITY_INVALIDATION_MAP.calendar_event).not.toContain(QK.todayBootstrap);
  });
});
