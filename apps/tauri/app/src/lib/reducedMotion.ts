import { useEffect, useState } from 'react';

interface ReducedMotionMediaQueryHost {
  matchMedia?: ((query: string) => { matches: boolean }) | undefined;
}

export const REDUCED_MOTION_QUERY = '(prefers-reduced-motion: reduce)';

export function prefersReducedMotion(host: ReducedMotionMediaQueryHost | undefined): boolean {
  if (!host || typeof host.matchMedia !== 'function') {
    return false;
  }
  try {
    return host.matchMedia(REDUCED_MOTION_QUERY).matches;
  } catch {
    return false;
  }
}

/**
 * Live-tracking React hook that mirrors `prefers-reduced-motion: reduce`.
 *
 * Three call sites had hand-rolled near-identical copies of
 * this hook — `ToastContainer`, `SubmitButton`, and `FooterBar`. Each
 * copy paired a `useState` initialized from `prefersReducedMotion()`
 * with a `useEffect` that subscribed to the matchMedia change event
 * (with the legacy-Safari `addListener` fallback). Centralising the
 * subscription keeps every consumer in lockstep when the listener
 * shape evolves and removes a 15-LOC repetition from each call site.
 */
export function useReducedMotion(): boolean {
  const [reduced, setReduced] = useState<boolean>(() =>
    prefersReducedMotion(typeof window === 'undefined' ? undefined : window),
  );
  useEffect(() => {
    if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return;
    const mql = window.matchMedia(REDUCED_MOTION_QUERY);
    const onChange = () => setReduced(mql.matches);
    if (typeof mql.addEventListener === 'function') {
      mql.addEventListener('change', onChange);
      return () => mql.removeEventListener('change', onChange);
    }
    // Fallback for older Safari (`addListener` was the deprecated API
    // before MediaQueryList grew an EventTarget interface).
    mql.addListener(onChange);
    return () => mql.removeListener(onChange);
  }, []);
  return reduced;
}
