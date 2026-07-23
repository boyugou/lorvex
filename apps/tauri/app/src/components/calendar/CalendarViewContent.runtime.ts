import type { CalendarViewMode } from './viewModePreference.logic';

type CalendarShortcutTarget = Pick<Window, 'addEventListener' | 'removeEventListener'>;

export type CalendarViewShortcutAction =
  | 'previous'
  | 'next'
  | 'today'
  | 'toggleViewMode';

interface CalendarViewShortcutEventLike {
  key: string;
  target: EventTarget | null;
  shiftKey?: boolean | undefined;
  metaKey?: boolean | undefined;
  ctrlKey?: boolean | undefined;
  altKey?: boolean | undefined;
}

interface CalendarViewShortcutRuntimeDeps {
  windowTarget?: CalendarShortcutTarget | undefined;
  viewMode: CalendarViewMode;
  shouldIgnoreShortcutTarget: (target: EventTarget | null) => boolean;
  goToPrevMonth: () => void;
  goToPrevWeek: () => void;
  goToNextMonth: () => void;
  goToNextWeek: () => void;
  goToToday: () => void;
  switchViewMode: (mode: CalendarViewMode) => void;
}

function hasCommandModifier(event: CalendarViewShortcutEventLike): boolean {
  return Boolean(event.metaKey || event.ctrlKey || event.altKey);
}

export function resolveCalendarViewShortcutAction(
  event: CalendarViewShortcutEventLike,
  shouldIgnoreShortcutTarget: (target: EventTarget | null) => boolean,
): CalendarViewShortcutAction | null {
  if (shouldIgnoreShortcutTarget(event.target)) return null;

  if (event.key === 'ArrowLeft' && !event.shiftKey) return 'previous';
  if (event.key === 'ArrowRight' && !event.shiftKey) return 'next';
  if (event.key === 't' && !hasCommandModifier(event)) return 'today';
  if (event.key === 'm' && !hasCommandModifier(event)) return 'toggleViewMode';

  return null;
}

export function runCalendarViewShortcutAction(
  action: CalendarViewShortcutAction,
  deps: Omit<CalendarViewShortcutRuntimeDeps, 'windowTarget' | 'shouldIgnoreShortcutTarget'>,
): void {
  if (action === 'previous') {
    (deps.viewMode === 'month' ? deps.goToPrevMonth : deps.goToPrevWeek)();
    return;
  }

  if (action === 'next') {
    (deps.viewMode === 'month' ? deps.goToNextMonth : deps.goToNextWeek)();
    return;
  }

  if (action === 'today') {
    deps.goToToday();
    return;
  }

  deps.switchViewMode(deps.viewMode === 'month' ? 'week' : 'month');
}

export function installCalendarViewShortcutRuntime({
  windowTarget,
  ...deps
}: CalendarViewShortcutRuntimeDeps): () => void {
  if (!windowTarget) return () => {};

  const onKeyDown = (event: KeyboardEvent) => {
    const action = resolveCalendarViewShortcutAction(event, deps.shouldIgnoreShortcutTarget);
    if (!action) return;

    event.preventDefault();
    runCalendarViewShortcutAction(action, deps);
  };

  windowTarget.addEventListener('keydown', onKeyDown);
  return () => windowTarget.removeEventListener('keydown', onKeyDown);
}
