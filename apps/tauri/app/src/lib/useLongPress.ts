import { useEffect, useRef } from 'react';
import { createLongPressController } from './useLongPress.logic';
import { useLazyRef } from './useLazyRef';

interface LongPressHandlers {
  onTouchStart: (e: React.TouchEvent) => void;
  onTouchEnd: () => void;
  onTouchMove: (e: React.TouchEvent) => void;
}

export const LONG_PRESS_IGNORE_ATTRIBUTE = 'data-long-press-ignore';
const LONG_PRESS_IGNORE_SELECTOR = `[${LONG_PRESS_IGNORE_ATTRIBUTE}]`;

type ClosestCapableTarget = {
  closest: (selector: string) => unknown;
};

type ContainsCapableTarget = {
  contains: (node: unknown) => boolean;
};

function hasClosest(value: EventTarget | null): value is EventTarget & ClosestCapableTarget {
  return typeof (value as { closest?: unknown } | null)?.closest === 'function';
}

function hasContains(value: EventTarget | null): value is EventTarget & ContainsCapableTarget {
  return typeof (value as { contains?: unknown } | null)?.contains === 'function';
}

function shouldIgnoreLongPressStart(
  target: EventTarget | null,
  currentTarget: EventTarget | null,
): boolean {
  if (!hasClosest(target)) return false;
  const ignoredTarget = target.closest(LONG_PRESS_IGNORE_SELECTOR);
  if (!ignoredTarget) return false;
  return !hasContains(currentTarget) || currentTarget.contains(ignoredTarget);
}

/**
 * Detect long-press (500ms hold) on touch devices.
 * Calls `onLongPress` with the touch coordinates when triggered.
 * Cancels if the finger moves more than 10px (scroll gesture).
 */
export function useLongPress(
  onLongPress: (x: number, y: number) => void,
): LongPressHandlers {
  const onLongPressRef = useRef(onLongPress);
  onLongPressRef.current = onLongPress;
  // `useLazyRef` runs the controller factory exactly once on first
  // render and pins the controller for the component's lifetime.
  // Each TaskCard mounts this hook, so a plain
  // `useRef(createLongPressController(...))` (which evaluates the
  // factory on every render and discards every result after the
  // first) would produce non-trivial GC pressure on long task
  // lists.
  const controllerRef = useLazyRef(() =>
    createLongPressController(({ x, y }) => onLongPressRef.current(x, y)),
  );

  const onTouchStart = (e: React.TouchEvent) => {
    if (shouldIgnoreLongPressStart(e.target, e.currentTarget)) return;
    const touch = e.touches[0];
    if (!touch) return;
    controllerRef.current.start({ x: touch.clientX, y: touch.clientY });
  };

  const onTouchEnd = () => {
    controllerRef.current.end();
  };

  const onTouchMove = (e: React.TouchEvent) => {
    const touch = e.touches[0];
    if (!touch) return;
    controllerRef.current.move({ x: touch.clientX, y: touch.clientY });
  };

  // controllerRef is a stable MutableRefObject from useLazyRef.
  useEffect(() => () => controllerRef.current.dispose(), [controllerRef]);

  return { onTouchStart, onTouchEnd, onTouchMove };
}
