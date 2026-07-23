import { describe, expect, test } from 'vitest';

import {
  parseCalendarViewModePreference,
  reconcileCalendarViewMode,
  serializeCalendarViewModePreference,
  syncCalendarViewModePreference,
} from './viewModePreference.logic';

// Calendar month/week toggle is preference-backed and synced — every
// device with the same calendar pref ends up on the same view. The
// `syncCalendarViewModePreference` helper coordinates four moving
// pieces (current local mode, the synced raw pref, an in-flight local
// write that hasn't echoed back yet, and a "settled" flag that latches
// after the user toggles a third time) so the UI doesn't flap when
// filesystem sync takes seconds to roundtrip a setPreference.

describe('parseCalendarViewModePreference', () => {
  test("returns 'month' as the safe default for null/garbage/unknown", () => {
    expect(parseCalendarViewModePreference(null)).toBe('month');
    expect(parseCalendarViewModePreference('')).toBe('month');
    expect(parseCalendarViewModePreference('day')).toBe('month');
    expect(parseCalendarViewModePreference('not json')).toBe('month');
  });

  test("returns 'week' only when the parsed preference is exactly 'week'", () => {
    expect(parseCalendarViewModePreference(JSON.stringify('week'))).toBe('week');
  });

  test("explicit 'month' parses to month", () => {
    expect(parseCalendarViewModePreference(JSON.stringify('month'))).toBe('month');
  });
});

describe('reconcileCalendarViewMode', () => {
  test('returns the preferred mode when current differs', () => {
    expect(reconcileCalendarViewMode('month', JSON.stringify('week'))).toBe('week');
    expect(reconcileCalendarViewMode('week', JSON.stringify('month'))).toBe('month');
  });

  test('returns the current mode (referential) when it matches the pref (no flicker)', () => {
    const mode = reconcileCalendarViewMode('week', JSON.stringify('week'));
    expect(mode).toBe('week');
  });
});

describe('syncCalendarViewModePreference — no pending local write', () => {
  test('no local write + matching pref: keep current mode, no pending state', () => {
    const next = syncCalendarViewModePreference({
      currentMode: 'month',
      rawPreference: JSON.stringify('month'),
      pendingLocalWrite: null,
      pendingLocalWriteSettled: false,
    });
    expect(next).toEqual({
      nextMode: 'month',
      nextPendingLocalWrite: null,
      nextPendingLocalWriteSettled: false,
    });
  });

  test('no local write + diverging pref: adopt the pref', () => {
    const next = syncCalendarViewModePreference({
      currentMode: 'month',
      rawPreference: JSON.stringify('week'),
      pendingLocalWrite: null,
      pendingLocalWriteSettled: false,
    });
    expect(next.nextMode).toBe('week');
    expect(next.nextPendingLocalWrite).toBeNull();
  });
});

describe('syncCalendarViewModePreference — pending local write in flight', () => {
  test('unsettled + currentMode already matches pendingLocalWrite: keep current', () => {
    // User just clicked "week"; we optimistically updated currentMode
    // to 'week' and set pendingLocalWrite='week'. The roundtrip hasn't
    // echoed yet (rawPreference may still say 'month'). Don't snap back.
    const next = syncCalendarViewModePreference({
      currentMode: 'week',
      rawPreference: JSON.stringify('month'),
      pendingLocalWrite: 'week',
      pendingLocalWriteSettled: false,
    });
    expect(next).toEqual({
      nextMode: 'week',
      nextPendingLocalWrite: 'week',
      nextPendingLocalWriteSettled: false,
    });
  });

  test('unsettled + currentMode lags pendingLocalWrite: nudge currentMode forward', () => {
    // Defensive: someone forced currentMode back to 'month' after the
    // optimistic write. Re-apply pendingLocalWrite so the UI matches
    // the user's clicked intent.
    const next = syncCalendarViewModePreference({
      currentMode: 'month',
      rawPreference: JSON.stringify('month'),
      pendingLocalWrite: 'week',
      pendingLocalWriteSettled: false,
    });
    expect(next.nextMode).toBe('week');
    expect(next.nextPendingLocalWrite).toBe('week');
    expect(next.nextPendingLocalWriteSettled).toBe(false);
  });

  test('settled + pref still diverges from pending + current matches pending: latch settled, keep current', () => {
    // Pref hasn't roundtripped yet but we already saw "settled" once;
    // refuse to flicker back. Hold currentMode at the user's intent.
    const next = syncCalendarViewModePreference({
      currentMode: 'week',
      rawPreference: JSON.stringify('month'),
      pendingLocalWrite: 'week',
      pendingLocalWriteSettled: true,
    });
    expect(next).toEqual({
      nextMode: 'week',
      nextPendingLocalWrite: 'week',
      nextPendingLocalWriteSettled: true,
    });
  });

  test('pref agrees with pendingLocalWrite: clear pending bookkeeping (sync caught up)', () => {
    const next = syncCalendarViewModePreference({
      currentMode: 'week',
      rawPreference: JSON.stringify('week'),
      pendingLocalWrite: 'week',
      pendingLocalWriteSettled: true,
    });
    expect(next).toEqual({
      nextMode: 'week',
      nextPendingLocalWrite: null,
      nextPendingLocalWriteSettled: false,
    });
  });

  test('pref agrees with pending but unsettled: hold pending (the unsettled branch always exits first)', () => {
    // When `pendingLocalWriteSettled: false`, the unsettled branch
    // returns unconditionally — the "clear pending if pref agrees"
    // arm is gated behind `settled: true`. This pins that ordering
    // so a refactor that flattens the branches can't accidentally
    // clear pending state on the very first roundtrip and leave the
    // UI vulnerable to a second peer-overwrite snap-back.
    const next = syncCalendarViewModePreference({
      currentMode: 'week',
      rawPreference: JSON.stringify('week'),
      pendingLocalWrite: 'week',
      pendingLocalWriteSettled: false,
    });
    expect(next).toEqual({
      nextMode: 'week',
      nextPendingLocalWrite: 'week',
      nextPendingLocalWriteSettled: false,
    });
  });

  test('peer overrode local write (pref no longer matches pending, current also drifted): hold pending', () => {
    // Settled, pref says 'month', currentMode also 'month' (drifted),
    // pending was 'week'. Final fallback arm: re-apply pending and
    // mark settled so the UI keeps showing user's intent until they
    // act again.
    const next = syncCalendarViewModePreference({
      currentMode: 'month',
      rawPreference: JSON.stringify('month'),
      pendingLocalWrite: 'week',
      pendingLocalWriteSettled: true,
    });
    expect(next).toEqual({
      nextMode: 'week',
      nextPendingLocalWrite: 'week',
      nextPendingLocalWriteSettled: true,
    });
  });
});

describe('serializeCalendarViewModePreference', () => {
  test('produces JSON that parseCalendarViewModePreference round-trips', () => {
    const a = serializeCalendarViewModePreference('month');
    const b = serializeCalendarViewModePreference('week');
    expect(parseCalendarViewModePreference(a)).toBe('month');
    expect(parseCalendarViewModePreference(b)).toBe('week');
  });
});
