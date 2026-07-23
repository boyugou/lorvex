import { memo, useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import type { Task } from '@/lib/ipc/tasks/models';
import { isTaskActive } from '@/lib/format';
import { useRuntimeProfile } from '@/lib/useRuntimeProfile';
import { CheckIcon, ClockIcon } from '../ui/icons';
import { useSwipeableTaskCardActions } from './useSwipeableTaskCardActions';

// --- Swipe gesture constants ---

/** Minimum horizontal displacement (px) to trigger the action. */
const SWIPE_THRESHOLD_PX = 80;
/** Minimum velocity (px/ms) to trigger the action regardless of distance. */
const SWIPE_VELOCITY_THRESHOLD = 0.5;
/** After this distance (px), decide whether this is a horizontal swipe or vertical scroll. */
const DIRECTION_LOCK_PX = 10;
/** Maximum card displacement (px) during dragging. */
const MAX_SWIPE_PX = 200;
/** Spring-back transition for cancelled swipes. */
const SNAP_BACK_TRANSITION = 'transform 0.3s cubic-bezier(0.25, 0.46, 0.45, 0.94)';
/** Exit slide transition after action is triggered. */
const EXIT_TRANSITION = 'transform 0.25s cubic-bezier(0.4, 0, 0.2, 1)';

interface SwipeableTaskCardProps {
  task: Task;
  children: ReactNode;
}

/**
 * Swipe gesture wrapper for TaskCard.  Mobile-only -- on desktop, renders
 * children directly without any wrapper DOM or event listeners.
 *
 * - Swipe right: complete the task (green reveal + checkmark)
 * - Swipe left: defer to tomorrow (amber reveal + clock)
 */
export const SwipeableTaskCard = memo(function SwipeableTaskCard({
  task,
  children,
}: SwipeableTaskCardProps) {
  const { runtimeClass } = useRuntimeProfile();
  const supportsSwipeGestures = runtimeClass === 'mobile';

  // On desktop, render children with zero overhead
  if (!supportsSwipeGestures) {
    return <>{children}</>;
  }

  return (
    <SwipeableTaskCardInner task={task}>
      {children}
    </SwipeableTaskCardInner>
  );
});

// ---------------------------------------------------------------------------
// Inner component — only mounted on mobile
// ---------------------------------------------------------------------------

const SwipeableTaskCardInner = memo(function SwipeableTaskCardInner({
  task,
  children,
}: SwipeableTaskCardProps) {
  // --- Refs for gesture tracking (no re-renders during drag) ---
  const cardRef = useRef<HTMLDivElement>(null);
  const startX = useRef(0);
  const startY = useRef(0);
  const startTime = useRef(0);
  const currentX = useRef(0);
  /** null = undecided, true = horizontal swipe locked, false = vertical scroll */
  const isHorizontalSwipe = useRef<boolean | null>(null);
  const actionFired = useRef(false);

  // --- State for visual feedback ---
  const [swiping, setSwiping] = useState(false);
  // prior implementation rendered both reveal
  // backgrounds (success-green for forward, warning-amber for defer)
  // unconditionally at `inset-0` while swiping, so DOM order alone
  // decided which color the user saw — the second reveal painted on
  // top of the first regardless of the actual gesture direction. We
  // now track the live delta sign on touchmove and render exactly
  // one reveal. `deltaSign` is `'forward'` when the gesture moves
  // in the user's reading-order direction (right in LTR, left in
  // RTL) and `'defer'` otherwise; `null` while undecided so we
  // suppress both reveals on the first pixel of motion before the
  // direction lock fires.
  const [deltaSign, setDeltaSign] = useState<'forward' | 'defer' | null>(null);

  const isActive = isTaskActive(task.status);

  // --- Helpers ---

  // Track the listener installed by the most recent `resetCardPosition`
  // call so we can evict it if another reset starts before the current
  // transition ends. Without this, a rapid back-to-back
  // swipe sequence leaves the previous listener attached; it fires
  // during the new transition and clobbers `card.style.transition`
  // mid-animation — user sees stuttering / no-snap on mobile. Also
  // cleared on unmount so a reset that races component teardown
  // doesn't keep a stale closure alive.
  const pendingResetCleanupRef = useRef<(() => void) | null>(null);

  const resetCardPosition = useCallback(() => {
    const card = cardRef.current;
    if (!card) return;
    // Evict any in-flight listener from an earlier reset before installing a new one.
    pendingResetCleanupRef.current?.();
    card.style.transition = SNAP_BACK_TRANSITION;
    card.style.transform = 'translateX(0)';
    currentX.current = 0;
    const cleanup = () => {
      card.style.transition = '';
      card.removeEventListener('transitionend', cleanup);
      if (pendingResetCleanupRef.current === cleanup) {
        pendingResetCleanupRef.current = null;
      }
    };
    pendingResetCleanupRef.current = cleanup;
    card.addEventListener('transitionend', cleanup);
  }, []);

  useEffect(
    () => () => {
      pendingResetCleanupRef.current?.();
      pendingResetCleanupRef.current = null;
    },
    [],
  );

  const {
    clearSwipeCompletionTimer,
    handleSwipeComplete,
    handleSwipeDefer,
  } = useSwipeableTaskCardActions(task, resetCardPosition);

  useEffect(() => clearSwipeCompletionTimer, [clearSwipeCompletionTimer]);

  // --- Touch event handlers ---

  const handleTouchStart = useCallback((e: React.TouchEvent) => {
    if (!isActive) return;

    const touch = e.touches[0];
    if (!touch) return;

    startX.current = touch.clientX;
    startY.current = touch.clientY;
    // Monotonic clock — system clock backsync mid-gesture would otherwise
    // produce a negative `elapsed` and a nonsense velocity.
    startTime.current = performance.now();
    currentX.current = 0;
    isHorizontalSwipe.current = null;
    actionFired.current = false;
    setDeltaSign(null);

    const card = cardRef.current;
    if (card) {
      card.style.transition = '';
    }
  }, [isActive]);

  const handleTouchMove = useCallback((e: React.TouchEvent) => {
    if (!isActive || actionFired.current) return;

    const touch = e.touches[0];
    if (!touch) return;

    const deltaX = touch.clientX - startX.current;
    const deltaY = touch.clientY - startY.current;
    const absDeltaX = Math.abs(deltaX);
    const absDeltaY = Math.abs(deltaY);

    // Direction lock: decide once after DIRECTION_LOCK_PX movement
    if (isHorizontalSwipe.current === null) {
      if (Math.max(absDeltaX, absDeltaY) < DIRECTION_LOCK_PX) return;

      if (absDeltaX > absDeltaY) {
        isHorizontalSwipe.current = true;
        setSwiping(true);
      } else {
        isHorizontalSwipe.current = false;
        return;
      }
    }

    if (!isHorizontalSwipe.current) return;

    // Clamp and apply transform directly (no state update -- ref-only for performance)
    const clampedDelta = Math.max(-MAX_SWIPE_PX, Math.min(MAX_SWIPE_PX, deltaX));
    currentX.current = clampedDelta;

    const card = cardRef.current;
    if (card) {
      card.style.transform = `translateX(${clampedDelta}px)`;
    }

    // track which reveal to render based on the
    // current sign of the gesture, mirrored against `dir="rtl"` so
    // the visual semantics ("end-of-line edge means complete") are
    // anchored to reading direction, not absolute screen
    // coordinates. We only flip on actual sign changes — re-setting
    // identical state is a no-op for React but the explicit guard
    // documents intent and avoids any future StrictMode oddity.
    if (clampedDelta !== 0) {
      const isRtl = typeof document !== 'undefined'
        && document.documentElement.dir === 'rtl';
      const swipeForward = isRtl ? clampedDelta < 0 : clampedDelta > 0;
      const next: 'forward' | 'defer' = swipeForward ? 'forward' : 'defer';
      setDeltaSign((prev) => (prev === next ? prev : next));
    }
  }, [isActive]);

  const handleTouchEnd = useCallback(() => {
    if (!isActive || actionFired.current) return;

    const displacement = currentX.current;
    const absDisplacement = Math.abs(displacement);
    const elapsed = performance.now() - startTime.current;
    const velocity = elapsed > 0 ? absDisplacement / elapsed : 0;

    const thresholdMet = absDisplacement >= SWIPE_THRESHOLD_PX || velocity >= SWIPE_VELOCITY_THRESHOLD;

    if (thresholdMet && isHorizontalSwipe.current) {
      actionFired.current = true;

      // Slide card off-screen in the swipe direction
      const card = cardRef.current;
      if (card) {
        const exitX = displacement > 0 ? window.innerWidth : -window.innerWidth;
        card.style.transition = EXIT_TRANSITION;
        card.style.transform = `translateX(${exitX}px)`;
      }

      // the gesture is anchored to the user's reading
      // direction, not to absolute screen coordinates. In LTR a
      // forward swipe (positive deltaX, "to the end") completes; in
      // RTL the visual end is on the left, so positive deltaX is the
      // *backward* direction (defer) and negative deltaX is forward
      // (complete). Mirror by inverting against `dir="rtl"`.
      const isRtl = typeof document !== 'undefined'
        && document.documentElement.dir === 'rtl';
      const swipeForward = isRtl ? displacement < 0 : displacement > 0;

      if (swipeForward) {
        void handleSwipeComplete();
      } else {
        void handleSwipeDefer();
      }
    } else {
      resetCardPosition();
    }

    setSwiping(false);
    setDeltaSign(null);
    isHorizontalSwipe.current = null;
  }, [isActive, handleSwipeComplete, handleSwipeDefer, resetCardPosition]);

  return (
    <div className="cv-swipeable-task-card relative overflow-hidden rounded-r-card">
      {/* idle-state edge affordances so touch users can
          discover swipe. Two thin colored gradients (success on the
          right edge to hint right-swipe-completes, warning on the left
          edge to hint left-swipe-defers). Only visible on coarse-
          pointer (touch) runtimes via `@media (pointer: coarse)` in
          index.css; hidden once a gesture starts so they don't compete
          with the full reveal backgrounds. */}
      {!swiping && (
        <>
          <div
            aria-hidden="true"
            className="cv-swipe-hint-right pointer-events-none absolute inset-y-0 end-0 w-1 rounded-none"
          />
          <div
            aria-hidden="true"
            className="cv-swipe-hint-left pointer-events-none absolute inset-y-0 start-0 w-1 rounded-none"
          />
        </>
      )}
      {/* Reveal backgrounds -- positioned behind the card, only shown
          while swiping.: render exactly one based on
          live deltaSign so the user sees the color matching the
          actual gesture direction, not whichever element happened
          to be last in DOM order. The reveal sits at `inset-0` and
          is pinned to the leading edge in forward (start-edge:
          checkmark on the start, RTL-aware) and trailing edge in
          defer. */}
      {swiping && deltaSign === 'forward' && (
        <div
          className="absolute inset-0 flex items-center ps-5 rounded-r-card bg-success"
          aria-hidden="true"
        >
          <CheckIcon className="w-6 h-6 text-white" />
        </div>
      )}
      {swiping && deltaSign === 'defer' && (
        <div
          className="absolute inset-0 flex items-center justify-end pe-5 rounded-r-card bg-warning"
          aria-hidden="true"
        >
          <ClockIcon className="w-6 h-6 text-white" />
        </div>
      )}

      {/* Card content slides horizontally */}
      <div
        ref={cardRef}
        className="relative z-[var(--z-sticky)]"
        style={{ willChange: swiping ? 'transform' : undefined }}
        onTouchStart={handleTouchStart}
        onTouchMove={handleTouchMove}
        onTouchEnd={handleTouchEnd}
      >
        {children}
      </div>
    </div>
  );
});
