const NEXT_RADIO_KEYS = new Set(['ArrowDown', 'ArrowRight']);
const PREVIOUS_RADIO_KEYS = new Set(['ArrowUp', 'ArrowLeft']);
const RADIO_NAVIGATION_KEYS = new Set([
  ...NEXT_RADIO_KEYS,
  ...PREVIOUS_RADIO_KEYS,
  'Home',
  'End',
]);
const RADIO_SELECT_KEYS = new Set([' ', 'Spacebar']);

export function moveRovingRadioIndex(
  currentIndex: number,
  optionCount: number,
  key: string,
): number {
  if (optionCount <= 0) return 0;
  const index = currentIndex >= 0 && currentIndex < optionCount ? currentIndex : 0;

  if (NEXT_RADIO_KEYS.has(key)) {
    return (index + 1) % optionCount;
  }
  if (PREVIOUS_RADIO_KEYS.has(key)) {
    return (index - 1 + optionCount) % optionCount;
  }
  if (key === 'Home') {
    return 0;
  }
  if (key === 'End') {
    return optionCount - 1;
  }
  return index;
}

export function handleRovingRadioGroupKeyDown({
  currentIndex,
  focusOption,
  key,
  onSelect,
  optionCount,
  preventDefault,
}: {
  currentIndex: number;
  focusOption: (index: number) => void;
  key: string;
  onSelect: (index: number) => void;
  optionCount: number;
  preventDefault: () => void;
}): boolean {
  if (!RADIO_NAVIGATION_KEYS.has(key) || optionCount <= 0) return false;

  preventDefault();
  const nextIndex = moveRovingRadioIndex(currentIndex, optionCount, key);
  onSelect(nextIndex);
  focusOption(nextIndex);
  return true;
}

export function handleRovingRadioSpaceKey({
  key,
  onSelect,
  preventDefault,
}: {
  key: string;
  onSelect: () => void;
  preventDefault: () => void;
}): boolean {
  if (!RADIO_SELECT_KEYS.has(key)) return false;
  preventDefault();
  onSelect();
  return true;
}
