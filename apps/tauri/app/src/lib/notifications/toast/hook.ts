/**
 * React subscription hook for the toast store.
 *
 * `useToasts` is the only entry point the renderer (`ToastContainer`)
 * uses to read the toast list reactively. The store is module-level;
 * each subscriber holds its own `useState` mirror updated on every
 * `notify()` call.
 */

import { useEffect, useState } from 'react';

import { getToastsSnapshot, subscribeToToasts } from './store';
import type { ToastItem } from './types';

export function useToasts(): ToastItem[] {
  const [state, setState] = useState<ToastItem[]>([]);
  useEffect(() => {
    setState(getToastsSnapshot());
    const unsubscribe = subscribeToToasts(setState);
    return unsubscribe;
  }, []);
  return state;
}
