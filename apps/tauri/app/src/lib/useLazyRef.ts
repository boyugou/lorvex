import { useRef, type MutableRefObject } from 'react';

const UNINITIALIZED: unique symbol = Symbol('useLazyRef.uninitialized');

/**
 * useLazyRef — call `factory` exactly once on first render, hold the
 * result for the component's lifetime. Replaces `useRef(createX())`,
 * which evaluates the factory every render and discards everything
 * after the first.
 *
 * The factory may legitimately return `null` or `undefined`; a unique
 * symbol sentinel distinguishes uninitialized from initialized state
 * so the factory still runs exactly once.
 *
 *
 */
export function useLazyRef<T>(factory: () => T): MutableRefObject<T> {
  const ref = useRef<T | typeof UNINITIALIZED>(UNINITIALIZED);
  if (ref.current === UNINITIALIZED) {
    ref.current = factory();
  }
  return ref as MutableRefObject<T>;
}
