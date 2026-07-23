export type ListPickerNavigationKey = 'ArrowDown' | 'ArrowUp';

export function clampListPickerFocusIndex(currentIndex: number, optionCount: number): number {
  if (optionCount <= 0) return -1;
  return Math.min(Math.max(currentIndex, 0), optionCount - 1);
}

export function getNextListPickerFocusIndex(
  key: ListPickerNavigationKey,
  currentIndex: number,
  optionCount: number,
): number {
  if (optionCount <= 0) return -1;
  if (currentIndex < 0) return 0;
  const current = clampListPickerFocusIndex(currentIndex, optionCount);
  if (key === 'ArrowDown') return Math.min(current + 1, optionCount - 1);
  return Math.max(current - 1, 0);
}
