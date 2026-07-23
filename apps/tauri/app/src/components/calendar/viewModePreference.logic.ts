import { parseStringPreference } from '@/lib/preferences/parser';

export type CalendarViewMode = 'month' | 'week';

export function parseCalendarViewModePreference(raw: string | null): CalendarViewMode {
  const parsed = parseStringPreference(raw, 'month');
  return parsed === 'week' ? 'week' : 'month';
}

export function reconcileCalendarViewMode(
  currentMode: CalendarViewMode,
  rawPreference: string | null,
): CalendarViewMode {
  const preferredMode = parseCalendarViewModePreference(rawPreference);
  return currentMode === preferredMode ? currentMode : preferredMode;
}

export function syncCalendarViewModePreference(args: {
  currentMode: CalendarViewMode;
  rawPreference: string | null;
  pendingLocalWrite: CalendarViewMode | null;
  pendingLocalWriteSettled: boolean;
}): {
  nextMode: CalendarViewMode;
  nextPendingLocalWrite: CalendarViewMode | null;
  nextPendingLocalWriteSettled: boolean;
} {
  const preferredMode = parseCalendarViewModePreference(args.rawPreference);

  if (args.pendingLocalWrite) {
    if (!args.pendingLocalWriteSettled) {
      return {
        nextMode: args.currentMode === args.pendingLocalWrite ? args.currentMode : args.pendingLocalWrite,
        nextPendingLocalWrite: args.pendingLocalWrite,
        nextPendingLocalWriteSettled: false,
      };
    }
    if (preferredMode !== args.pendingLocalWrite && args.currentMode === args.pendingLocalWrite) {
      return {
        nextMode: args.currentMode,
        nextPendingLocalWrite: args.pendingLocalWrite,
        nextPendingLocalWriteSettled: true,
      };
    }
    if (preferredMode === args.pendingLocalWrite) {
      return {
        nextMode: args.pendingLocalWrite,
        nextPendingLocalWrite: null,
        nextPendingLocalWriteSettled: false,
      };
    }
    return {
      nextMode: args.pendingLocalWrite,
      nextPendingLocalWrite: args.pendingLocalWrite,
      nextPendingLocalWriteSettled: true,
    };
  }

  return {
    nextMode: reconcileCalendarViewMode(args.currentMode, args.rawPreference),
    nextPendingLocalWrite: null,
    nextPendingLocalWriteSettled: false,
  };
}

export function serializeCalendarViewModePreference(mode: CalendarViewMode): string {
  return JSON.stringify(mode);
}
