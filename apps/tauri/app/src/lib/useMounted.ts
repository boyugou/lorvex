import { useEffect, useRef, type RefObject } from 'react';

/**
 * Returns a ref whose `.current` is `true` while the component is
 * mounted and `false` after unmount.
 *
 * **Read this `.current` only from inside `setTimeout` / Promise
 * callbacks / event handlers — i.e. callers that fire AFTER React
 * has committed.** The ref starts `true` before any effect has
 * run, so consulting it during the very first render reports
 * "mounted" even on a render that React will later abort
 * (Suspense, ErrorBoundary tear-down, StrictMode double-mount).
 * For sites that need commit-accurate semantics, prefer the
 * conventional pattern of starting `false` and setting `true` in a
 * layout effect.
 *
 * The current shape is correct for every observed call site, which
 * uses the ref to gate `setState` against a unmounted component
 * after a finished IPC promise.
 */
export function useMounted(): RefObject<boolean> {
  const ref = useRef(true);
  useEffect(() => {
    ref.current = true;
    return () => {
      ref.current = false;
    };
  }, []);
  return ref;
}
