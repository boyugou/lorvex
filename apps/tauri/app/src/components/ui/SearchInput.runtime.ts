export interface SearchInputKeyDownEvent {
  key: string;
  preventDefault: () => void;
  stopPropagation: () => void;
}

export function handleSearchInputKeyDown(
  event: SearchInputKeyDownEvent,
  clear: () => void,
  blur: () => void,
): boolean {
  if (event.key !== 'Escape') {
    return false;
  }

  event.preventDefault();
  event.stopPropagation();
  clear();
  blur();
  return true;
}
