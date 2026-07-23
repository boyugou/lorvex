import { useCallback, useEffect, useMemo, useState, type Dispatch, type SetStateAction } from 'react';

interface PickerOption {
  key: string;
}

function getCurrentOptionIndex(currentKey: string, options: readonly PickerOption[]): number {
  const currentIndex = options.findIndex((option) => option.key === currentKey);
  return currentIndex >= 0 ? currentIndex : 0;
}

export function useCurrentPickerFocusIndex({
  currentKey,
  options,
}: {
  currentKey: string;
  options: readonly PickerOption[];
}) {
  const optionKeys = useMemo(
    () => options.map((option) => option.key).join('\0'),
    [options],
  );
  const currentIndex = useMemo(
    () => getCurrentOptionIndex(currentKey, options),
    [currentKey, options],
  );
  const anchorKey = `${currentKey}\0${optionKeys}`;
  const [focusState, setFocusState] = useState(() => ({
    anchorKey,
    focusIdx: currentIndex,
  }));
  const focusIdx = focusState.anchorKey === anchorKey ? focusState.focusIdx : currentIndex;

  useEffect(() => {
    if (focusState.anchorKey !== anchorKey) {
      setFocusState({ anchorKey, focusIdx: currentIndex });
    }
  }, [anchorKey, currentIndex, focusState.anchorKey]);

  const setFocusIdx: Dispatch<SetStateAction<number>> = useCallback((next) => {
    setFocusState((prev) => {
      const prevFocusIdx = prev.anchorKey === anchorKey ? prev.focusIdx : currentIndex;
      const focusIdx =
        typeof next === 'function'
          ? (next as (prev: number) => number)(prevFocusIdx)
          : next;
      return { anchorKey, focusIdx };
    });
  }, [anchorKey, currentIndex]);

  return [focusIdx, setFocusIdx] as const;
}
