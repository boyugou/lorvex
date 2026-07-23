import { useEffect } from 'react';
import { createBrowserVisualViewportInsetHost } from './useVisualViewport.runtime';

export interface VisualViewportInsetHost {
  getInnerHeight: () => number;
  getOffsetTop: () => number;
  getViewportHeight: () => number;
  onViewportChange: (listener: () => void) => () => void;
  setInsetPx: (insetPx: number) => void;
  clearInset: () => void;
}

export function computeVisualViewportInset(
  innerHeight: number,
  viewportHeight: number,
  offsetTop: number,
): number {
  return Math.max(0, innerHeight - viewportHeight - offsetTop);
}

/**
 * Android shrink `visualViewport` when the soft
 * keyboard opens but do NOT reflow `position: fixed` elements anchored
 * to the bottom. Subscribe to `visualViewport.resize` and expose the
 * keyboard inset as the CSS var `--kb-inset` on `<html>` so callers can
 * use `bottom: calc(env(safe-area-inset-bottom) + var(--kb-inset, 0px))`
 * without needing React state plumbing.
 *
 * Mounted once at the application root; a no-op on runtimes without
 * `visualViewport` (older desktops) where the var stays at 0 px.
 */
export function installVisualViewportInsetTracking(
  host: VisualViewportInsetHost | null = createBrowserVisualViewportInsetHost(),
): () => void {
  if (!host) return () => {};
  const update = () => {
    host.setInsetPx(
      computeVisualViewportInset(
        host.getInnerHeight(),
        host.getViewportHeight(),
        host.getOffsetTop(),
      ),
    );
  };

  update();
  const unsubscribe = host.onViewportChange(update);
  return () => {
    unsubscribe();
    host.clearInset();
  };
}

export function useVisualViewportInset() {
  useEffect(() => installVisualViewportInsetTracking(), []);
}
