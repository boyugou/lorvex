import { useEffect, useState } from 'react';

import {
  createBrowserDebounceTimerHost,
  scheduleDebouncedUpdate,
} from './useDebounced.runtime';

const debounceTimerHost = createBrowserDebounceTimerHost();

export function useDebounced<T>(value: T, delay: number): T {
  const [debounced, setDebounced] = useState(value);

  useEffect(() => {
    return scheduleDebouncedUpdate(
      debounceTimerHost,
      () => setDebounced(value),
      delay,
    );
  }, [value, delay]);

  return debounced;
}
