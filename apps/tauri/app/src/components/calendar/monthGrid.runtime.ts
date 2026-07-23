export const MOBILE_BREAKPOINT_PX = 480;

interface MonthGridMediaChangeEventLike {
  matches: boolean;
}

interface MonthGridMediaQueryLike {
  matches: boolean;
  addEventListener?: ((type: 'change', listener: (event: MonthGridMediaChangeEventLike) => void) => void) | undefined;
  removeEventListener?: ((type: 'change', listener: (event: MonthGridMediaChangeEventLike) => void) => void) | undefined;
}

interface MonthGridMediaRuntimeDeps {
  createMediaQueryList: () => MonthGridMediaQueryLike;
  onMatchesChange: (matches: boolean) => void;
}

export function readMonthGridNarrowMatch(createMediaQueryList: () => MonthGridMediaQueryLike): boolean {
  try {
    return createMediaQueryList().matches;
  } catch {
    return false;
  }
}

export function installMonthGridMediaRuntime(deps: MonthGridMediaRuntimeDeps): () => void {
  let mediaQuery: MonthGridMediaQueryLike;
  try {
    mediaQuery = deps.createMediaQueryList();
  } catch {
    return () => {};
  }

  const onChange = (event: MonthGridMediaChangeEventLike) => {
    deps.onMatchesChange(event.matches);
  };

  if (
    typeof mediaQuery.addEventListener === 'function'
    && typeof mediaQuery.removeEventListener === 'function'
  ) {
    mediaQuery.addEventListener('change', onChange);
    return () => mediaQuery.removeEventListener?.('change', onChange);
  }

  return () => {};
}
