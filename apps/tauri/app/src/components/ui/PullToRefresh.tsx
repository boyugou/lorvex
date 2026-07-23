import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import { useRuntimeProfile } from '@/lib/useRuntimeProfile';

const THRESHOLD = 60;
const MAX_PULL = 100;

interface PullToRefreshProps {
  onRefresh: () => Promise<void>;
  children: ReactNode;
}

/**
 * Touch-based pull-to-refresh wrapper for mobile runtimes.
 * Finds the nearest scrolling ancestor of the touch target and only activates
 * when that element is scrolled to the top — otherwise scroll and pull compete.
 */
function findScrollableAncestor(start: Element | null, boundary: Element | null): Element | null {
  let el: Element | null = start;
  while (el && el !== boundary) {
    const overflowY = window.getComputedStyle(el).overflowY;
    if ((overflowY === 'auto' || overflowY === 'scroll') && el.scrollHeight > el.clientHeight) {
      return el;
    }
    el = el.parentElement;
  }
  return null;
}

export function PullToRefresh({ onRefresh, children }: PullToRefreshProps) {
  const runtimeProfile = useRuntimeProfile();
  const isMobile = runtimeProfile.runtimeClass === 'mobile';

  const [pullDistance, setPullDistance] = useState(0);
  const [refreshing, setRefreshing] = useState(false);

  const touchStartYRef = useRef(0);
  const pullActiveRef = useRef(false);
  // Track the resolved scrollable ancestor for the active gesture so the
  // non-passive touchmove handler can decide to preventDefault() without
  // re-walking the DOM on every move event.
  const activeScrollerRef = useRef<Element | null>(null);
  const refreshingRef = useRef(false);
  const pullDistanceRef = useRef(0);
  // track whether we've already fired the threshold-cross
  // haptic so a finger jiggling around the activation line doesn't trigger
  // a buzz storm. Resets on touchstart (next gesture) and on any move that
  // backs the pull below threshold.
  const thresholdCrossedRef = useRef(false);
  const rootRef = useRef<HTMLDivElement | null>(null);

  const handleTouchStart = useCallback(
    (e: React.TouchEvent<HTMLDivElement>) => {
      if (refreshingRef.current) return;
      // Walk up from the touch target to find the nearest scrolling ancestor
      // within this component; only activate when it is at the top (scrollTop === 0).
      const target = e.target instanceof Element ? e.target : null;
      const scroller = findScrollableAncestor(target, rootRef.current);
      if (scroller && scroller.scrollTop > 0) {
        activeScrollerRef.current = null;
        return;
      }
      // `touches[0]` can legitimately be undefined on edge
      // devices that deliver an empty TouchList (stylus handoff, palm-
      // rejection cancellation) — the `!` assertion would throw inside
      // a synthetic-event handler and bubble to window error.
      const firstTouch = e.touches[0];
      if (!firstTouch) return;
      touchStartYRef.current = firstTouch.clientY;
      pullActiveRef.current = true;
      thresholdCrossedRef.current = false;
      activeScrollerRef.current = scroller;
    },
    [],
  );

  // React's synthetic touchmove is registered passively (React 19 default for
  // touch events), so calling preventDefault() inside it is a no-op and the platform's
  // rubber-band animation visibly competes with the pull-to-refresh transform.
  // Wire a manual non-passive listener on the root so we can suppress the
  // default scroll exactly when the gesture is "pulling down at scrollTop=0".
  useEffect(() => {
    if (!isMobile) return;
    const root = rootRef.current;
    if (!root) return;
    const handler = (e: TouchEvent) => {
      if (!pullActiveRef.current || refreshingRef.current) return;
      const firstTouch = e.touches[0];
      if (!firstTouch) return;
      const currentY = firstTouch.clientY;
      const delta = currentY - touchStartYRef.current;
      if (delta <= 0) {
        if (pullDistanceRef.current !== 0) {
          pullDistanceRef.current = 0;
          setPullDistance(0);
        }
        return;
      }
      const scroller = activeScrollerRef.current;
      // Bail out if the scroller scrolled away from the top mid-gesture
      // (e.g. inertial flick that hasn't fully settled). Without this, a
      // pull that starts at the top but races against a pending scroll
      // commit would briefly preventDefault() while the list is below the
      // fold, which feels like a stuck UI.
      if (scroller && scroller.scrollTop > 0) return;
      // Block the native rubber-band: once we've decided this gesture is a
      // pull (scrollTop === 0 AND finger moving down), the browser's
      // overscroll animation must yield so our transform owns the visuals.
      if (e.cancelable) e.preventDefault();
      // Apply diminishing returns past threshold for a rubber-band feel
      const clamped = Math.min(delta * 0.5, MAX_PULL);
      // fire a single short haptic the moment the pull
      // crosses the activation threshold (matches Android native PTR
      // affordance). Use `navigator.vibrate` when available — it's a no-op
      // on desktop browsers and macOS Safari, so this is safe to call
      // unconditionally on the mobile runtime branch.
      if (clamped >= THRESHOLD && !thresholdCrossedRef.current) {
        thresholdCrossedRef.current = true;
        if (typeof navigator !== 'undefined' && typeof navigator.vibrate === 'function') {
          try {
            navigator.vibrate(10);
          } catch {
            // Some embeddings throw `NotAllowedError` if the page hasn't
            // received a user gesture — but we are inside a touchmove
            // handler, so this should not normally trip. Swallow either
            // way: failing to vibrate is never worth interrupting the pull.
          }
        }
      } else if (clamped < THRESHOLD && thresholdCrossedRef.current) {
        // Re-arm so the user can pull below + re-cross within one gesture.
        thresholdCrossedRef.current = false;
      }
      pullDistanceRef.current = clamped;
      setPullDistance(clamped);
    };
    root.addEventListener('touchmove', handler, { passive: false });
    return () => {
      root.removeEventListener('touchmove', handler);
    };
  }, [isMobile]);

  const handleTouchEnd = useCallback(async () => {
    if (!pullActiveRef.current) return;
    pullActiveRef.current = false;
    activeScrollerRef.current = null;
    if (pullDistanceRef.current >= THRESHOLD && !refreshingRef.current) {
      refreshingRef.current = true;
      setRefreshing(true);
      pullDistanceRef.current = THRESHOLD;
      setPullDistance(THRESHOLD); // Snap to threshold while refreshing
      try {
        await onRefresh();
      } finally {
        refreshingRef.current = false;
        setRefreshing(false);
        pullDistanceRef.current = 0;
        setPullDistance(0);
      }
    } else {
      pullDistanceRef.current = 0;
      setPullDistance(0);
    }
  }, [onRefresh]);

  // On desktop, render children without any pull-to-refresh wrapper
  if (!isMobile) {
    return <>{children}</>;
  }

  const indicatorOpacity = Math.min(pullDistance / THRESHOLD, 1);
  const indicatorScale = 0.5 + indicatorOpacity * 0.5;

  return (
    <div
      ref={rootRef}
      className="relative h-full"
      onTouchStart={handleTouchStart}
      onTouchEnd={() => { void handleTouchEnd(); }}
      onTouchCancel={() => { void handleTouchEnd(); }}
    >
      {/* Pull indicator */}
      <div
        className="absolute start-0 end-0 flex items-center justify-center pointer-events-none z-[var(--z-sticky)] transition-[height] duration-200 ease-out overflow-hidden"
        style={{ height: pullDistance > 0 || refreshing ? `${pullDistance}px` : '0px' }}
      >
        <div
          className="transition-[opacity,transform] duration-200 ease-out"
          style={{ opacity: indicatorOpacity, transform: `scale(${indicatorScale})` }}
        >
          {refreshing ? (
            <svg
              className="w-6 h-6 text-accent animate-spin"
              viewBox="0 0 24 24"
              fill="none"
              aria-hidden="true"
            >
              <circle cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="2.5" className="opacity-20" />
              <path d="M12 2a10 10 0 0 1 10 10" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" />
            </svg>
          ) : (
            <svg
              className="w-6 h-6 text-text-muted transition-transform duration-200"
              style={{ transform: indicatorOpacity >= 1 ? 'rotate(180deg)' : 'rotate(0deg)' }}
              viewBox="0 0 24 24"
              fill="none"
              aria-hidden="true"
            >
              <path d="M12 4v12M12 16l-4-4M12 16l4-4" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          )}
        </div>
      </div>

      {/* Content shifted down by pull distance */}
      <div
        className="h-full transition-transform duration-200 ease-out"
        style={{ transform: pullDistance > 0 || refreshing ? `translateY(${pullDistance}px)` : undefined }}
      >
        {children}
      </div>
    </div>
  );
}
