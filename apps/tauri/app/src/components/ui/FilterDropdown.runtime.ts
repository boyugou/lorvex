interface FilterDropdownTypeAheadOption {
  label: string;
}

export interface FilterDropdownTypeAheadState {
  timer: unknown | null;
  buffer: string;
}

export interface FilterDropdownTypeAheadTimerHost {
  clearTimeout: (handle: unknown) => void;
  setTimeout: (callback: () => void, delayMs: number) => unknown;
}

export function createBrowserFilterDropdownTypeAheadTimerHost(): FilterDropdownTypeAheadTimerHost {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

interface FilterDropdownInitialFocusHost {
  requestAnimationFrame: (callback: () => void) => unknown;
  cancelAnimationFrame?: ((handle: unknown) => void) | undefined;
  focusOption: () => void;
}

const TYPE_AHEAD_RESET_DELAY_MS = 500;

export function findFilterDropdownTypeAheadMatch(
  options: readonly FilterDropdownTypeAheadOption[],
  focusedIndex: number,
  buffer: string,
): number | null {
  if (options.length === 0 || buffer.length === 0) return null;

  const normalizedBuffer = buffer.toLowerCase();
  const startIndex = (Math.max(focusedIndex, -1) + 1) % options.length;
  for (let offset = 0; offset < options.length; offset += 1) {
    const index = (startIndex + offset) % options.length;
    const option = options[index];
    if (option?.label.toLowerCase().startsWith(normalizedBuffer)) {
      return index;
    }
  }

  return null;
}

export function advanceFilterDropdownTypeAhead({
  state,
  typedChar,
  options,
  focusedIndex,
  timerHost,
  resetDelayMs = TYPE_AHEAD_RESET_DELAY_MS,
}: {
  state: FilterDropdownTypeAheadState;
  typedChar: string;
  options: readonly FilterDropdownTypeAheadOption[];
  focusedIndex: number;
  timerHost: FilterDropdownTypeAheadTimerHost;
  resetDelayMs?: number;
}): number | null {
  if (state.timer !== null) {
    timerHost.clearTimeout(state.timer);
  }

  state.buffer += typedChar.toLowerCase();
  state.timer = timerHost.setTimeout(() => {
    state.buffer = '';
    state.timer = null;
  }, resetDelayMs);

  return findFilterDropdownTypeAheadMatch(options, focusedIndex, state.buffer);
}

export function clearFilterDropdownTypeAhead(
  state: FilterDropdownTypeAheadState,
  clearTimeout: (handle: unknown) => void,
): void {
  if (state.timer !== null) {
    clearTimeout(state.timer);
  }
  state.timer = null;
  state.buffer = '';
}

export function scheduleFilterDropdownInitialFocus({
  requestAnimationFrame,
  cancelAnimationFrame,
  focusOption,
}: FilterDropdownInitialFocusHost): () => void {
  let active = true;
  const handle = requestAnimationFrame(() => {
    if (!active) return;
    focusOption();
  });

  return () => {
    active = false;
    cancelAnimationFrame?.(handle);
  };
}
