import { getCurrentHHMM } from './useCurrentTime.logic';

export function readCurrentTimeValue(
  timezone?: string,
  now: Date = new Date(),
): string {
  return getCurrentHHMM(timezone, now);
}

export function reconcileCurrentTimeValue(
  currentValue: string,
  timezone?: string,
  now: Date = new Date(),
): string {
  const nextValue = readCurrentTimeValue(timezone, now);
  return nextValue === currentValue ? currentValue : nextValue;
}
