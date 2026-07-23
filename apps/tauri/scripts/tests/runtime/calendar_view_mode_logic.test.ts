import assert from 'node:assert/strict';
import test from 'node:test';

import {
  parseCalendarViewModePreference,
  reconcileCalendarViewMode,
  serializeCalendarViewModePreference,
  syncCalendarViewModePreference,
} from '../../../app/src/components/calendar/viewModePreference.logic';

test('calendar view mode preference parser only accepts canonical month/week values', () => {
  assert.equal(parseCalendarViewModePreference(null), 'month');
  assert.equal(parseCalendarViewModePreference('"week"'), 'week');
  assert.equal(parseCalendarViewModePreference('"month"'), 'month');
  assert.equal(parseCalendarViewModePreference('"timeline"'), 'month');
  assert.equal(parseCalendarViewModePreference('{oops'), 'month');
});

test('calendar view mode reconcile tracks external preference changes for mounted controllers', () => {
  assert.equal(reconcileCalendarViewMode('month', '"week"'), 'week');
  assert.equal(reconcileCalendarViewMode('week', '"month"'), 'month');
  assert.equal(reconcileCalendarViewMode('week', '"week"'), 'week');
});

test('calendar view mode sync preserves a pending local toggle across one stale preference refetch', () => {
  const optimisticEcho = syncCalendarViewModePreference({
    currentMode: 'week',
    rawPreference: '"week"',
    pendingLocalWrite: 'week',
    pendingLocalWriteSettled: false,
  });
  assert.deepEqual(optimisticEcho, {
    nextMode: 'week',
    nextPendingLocalWrite: 'week',
    nextPendingLocalWriteSettled: false,
  });

  const staleRefetchBeforeSettle = syncCalendarViewModePreference({
    currentMode: optimisticEcho.nextMode,
    rawPreference: '"month"',
    pendingLocalWrite: optimisticEcho.nextPendingLocalWrite,
    pendingLocalWriteSettled: optimisticEcho.nextPendingLocalWriteSettled,
  });
  assert.deepEqual(staleRefetchBeforeSettle, {
    nextMode: 'week',
    nextPendingLocalWrite: 'week',
    nextPendingLocalWriteSettled: false,
  });

  const staleRefetchAfterSettle = syncCalendarViewModePreference({
    currentMode: staleRefetchBeforeSettle.nextMode,
    rawPreference: '"month"',
    pendingLocalWrite: staleRefetchBeforeSettle.nextPendingLocalWrite,
    pendingLocalWriteSettled: true,
  });
  assert.deepEqual(staleRefetchAfterSettle, {
    nextMode: 'week',
    nextPendingLocalWrite: 'week',
    nextPendingLocalWriteSettled: true,
  });

  const acknowledgedWrite = syncCalendarViewModePreference({
    currentMode: staleRefetchAfterSettle.nextMode,
    rawPreference: '"week"',
    pendingLocalWrite: staleRefetchAfterSettle.nextPendingLocalWrite,
    pendingLocalWriteSettled: staleRefetchAfterSettle.nextPendingLocalWriteSettled,
  });
  assert.deepEqual(acknowledgedWrite, {
    nextMode: 'week',
    nextPendingLocalWrite: null,
    nextPendingLocalWriteSettled: false,
  });
});

test('calendar view mode serializer matches the raw preference wire format used by setPreference', () => {
  assert.equal(serializeCalendarViewModePreference('month'), '"month"');
  assert.equal(serializeCalendarViewModePreference('week'), '"week"');
});
