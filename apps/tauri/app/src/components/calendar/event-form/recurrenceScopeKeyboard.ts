import { type RecurrenceScope } from './recurrenceScope';

export const RECURRENCE_SCOPE_ORDER: readonly RecurrenceScope[] = [
  'thisOnly',
  'thisAndFollowing',
  'allInSeries',
];

const NEXT_KEYS = new Set(['ArrowDown', 'ArrowRight']);
const PREV_KEYS = new Set(['ArrowUp', 'ArrowLeft']);
const NAVIGATION_KEYS = new Set([...NEXT_KEYS, ...PREV_KEYS, 'Home', 'End']);

interface RecurrenceScopeKeyboardNavigationArgs {
  current: RecurrenceScope;
  key: string;
  preventDefault: () => void;
  selectScope: (scope: RecurrenceScope) => void;
}

function scopeAt(index: number): RecurrenceScope {
  return RECURRENCE_SCOPE_ORDER[index] ?? 'thisOnly';
}

export function moveRecurrenceScopeSelection(
  current: RecurrenceScope,
  key: string,
): RecurrenceScope {
  const currentIndex = RECURRENCE_SCOPE_ORDER.indexOf(current);
  const index = currentIndex >= 0 ? currentIndex : 0;

  if (NEXT_KEYS.has(key)) {
    return scopeAt((index + 1) % RECURRENCE_SCOPE_ORDER.length);
  }
  if (PREV_KEYS.has(key)) {
    return scopeAt((index - 1 + RECURRENCE_SCOPE_ORDER.length) % RECURRENCE_SCOPE_ORDER.length);
  }
  if (key === 'Home') {
    return scopeAt(0);
  }
  if (key === 'End') {
    return scopeAt(RECURRENCE_SCOPE_ORDER.length - 1);
  }
  return current;
}

export function handleRecurrenceScopeKeyboardNavigation({
  current,
  key,
  preventDefault,
  selectScope,
}: RecurrenceScopeKeyboardNavigationArgs): boolean {
  if (!NAVIGATION_KEYS.has(key)) return false;

  preventDefault();
  const next = moveRecurrenceScopeSelection(current, key);
  if (next !== current) {
    selectScope(next);
  }
  return true;
}
