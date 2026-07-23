import {
  cloneElement,
  isValidElement,
  useCallback,
  useEffect,
  useId,
  useLayoutEffect,
  useRef,
  useState,
  type ReactElement,
  type ReactNode,
} from 'react';

import { OverlayPortal } from './overlay/OverlayPortal';
import {
  clearTooltipTimer,
  computeTooltipPosition,
  createBrowserTooltipTimerHost,
  installTooltipDismissRuntime,
  mergeTooltipTriggerDescribedBy,
  scheduleTooltipTimer,
  type TooltipSide,
} from './Tooltip.runtime';

/**
 * Styled tooltip that replaces native `title=` attributes.
 *
 * Why a custom component: native `title` has a ~500 ms browser delay we
 * can't tune, ignores dark-mode theming, is invisible on touch devices,
 * and carries no ARIA semantics. This tooltip:
 *   - Shows on mouseenter/focus (keyboard-accessible), hides on leave/blur/Escape.
 *   - Suppresses itself on touch (long-press affordances live elsewhere).
 *   - Wires `aria-describedby` so screen readers announce the hint.
 *   - Renders into a portal so it escapes overflow:hidden containers.
 *
 * The show/hide state machine lives in `useTooltipState` so it can be
 * unit-tested without mounting React. The component here is the thin
 * DOM + positioning + portal shell around that hook.
 */

interface TooltipProps {
  label: string;
  children: ReactNode;
  side?: TooltipSide;
  sideOffset?: number;
  disabled?: boolean;
  delayMs?: number;
}

interface TooltipTriggerChildProps {
  'aria-describedby'?: string | undefined;
}

export const TOOLTIP_DEFAULT_DELAY_MS = 400;
const TOOLTIP_HIDE_DELAY_MS = 80;
const tooltipTimerHost = createBrowserTooltipTimerHost();

// ---------------------------------------------------------------------------
// Pure state machine — extracted as a hook so it can be exercised by
// scripts/tests/runtime/tooltip.test.ts without needing jsdom.
// ---------------------------------------------------------------------------

type TooltipVisibility = 'closed' | 'opening' | 'open' | 'closing';

interface UseTooltipStateOptions {
  delayMs?: number;
  hideDelayMs?: number;
  disabled?: boolean;
  /** Injection points for deterministic tests. Defaults to native timers. */
  setTimer?: (fn: () => void, ms: number) => unknown;
  clearTimer?: (handle: unknown) => void;
}

interface UseTooltipState {
  visibility: TooltipVisibility;
  isMounted: boolean;
  show: () => void;
  hide: () => void;
  hideImmediately: () => void;
  cancel: () => void;
}

/**
 * Pure tooltip state machine. Keeps track of whether the tooltip is
 * currently `closed` | `opening` (delay pending) | `open` | `closing`
 * (fade-out transition). All timer operations funnel through the
 * injected `setTimer` / `clearTimer` so tests can drive the state
 * deterministically without real timers.
 */
function useTooltipState(options: UseTooltipStateOptions = {}): UseTooltipState {
  const {
    delayMs = TOOLTIP_DEFAULT_DELAY_MS,
    hideDelayMs = TOOLTIP_HIDE_DELAY_MS,
    disabled = false,
    setTimer,
    clearTimer,
  } = options;

  const [visibility, setVisibility] = useState<TooltipVisibility>('closed');
  const timerRef = useRef<unknown>(null);

  const schedule = useCallback(
    (fn: () => void, ms: number) => {
      if (setTimer) return setTimer(fn, ms);
      return scheduleTooltipTimer(tooltipTimerHost, fn, ms);
    },
    [setTimer],
  );

  const unschedule = useCallback(
    (handle: unknown) => {
      if (handle == null) return;
      if (clearTimer) {
        clearTimer(handle);
        return;
      }
      clearTooltipTimer(tooltipTimerHost, handle);
    },
    [clearTimer],
  );

  const cancel = useCallback(() => {
    if (timerRef.current != null) {
      unschedule(timerRef.current);
      timerRef.current = null;
    }
  }, [unschedule]);

  const show = useCallback(() => {
    if (disabled) return;
    cancel();
    setVisibility((prev) => (prev === 'open' ? 'open' : 'opening'));
    timerRef.current = schedule(() => {
      timerRef.current = null;
      setVisibility('open');
    }, delayMs);
  }, [cancel, delayMs, disabled, schedule]);

  const hide = useCallback(() => {
    cancel();
    setVisibility((prev) => {
      if (prev === 'closed') return 'closed';
      if (prev === 'opening') return 'closed';
      return 'closing';
    });
    timerRef.current = schedule(() => {
      timerRef.current = null;
      setVisibility('closed');
    }, hideDelayMs);
  }, [cancel, hideDelayMs, schedule]);

  const hideImmediately = useCallback(() => {
    cancel();
    setVisibility('closed');
  }, [cancel]);

  useEffect(
    () => () => {
      // Cleanup on unmount so dangling timers don't fire.
      if (timerRef.current != null) unschedule(timerRef.current);
      timerRef.current = null;
    },
    [unschedule],
  );

  return {
    visibility,
    isMounted: visibility !== 'closed',
    show,
    hide,
    hideImmediately,
    cancel,
  };
}

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

function renderTooltipTriggerChild(
  children: ReactNode,
  tooltipDescriptionId: string | undefined,
): ReactNode {
  if (!isValidElement(children)) return children;

  const triggerChild = children as ReactElement<TooltipTriggerChildProps>;
  const describedBy = mergeTooltipTriggerDescribedBy(
    triggerChild.props['aria-describedby'],
    tooltipDescriptionId,
  );

  if (describedBy === triggerChild.props['aria-describedby']) return children;

  return cloneElement(triggerChild, {
    'aria-describedby': describedBy,
  });
}

export function Tooltip({
  label,
  children,
  side = 'top',
  sideOffset = 6,
  disabled = false,
  delayMs = TOOLTIP_DEFAULT_DELAY_MS,
}: TooltipProps) {
  const id = useId();
  const triggerRef = useRef<HTMLSpanElement | null>(null);
  const tooltipRef = useRef<HTMLDivElement | null>(null);
  const [coords, setCoords] = useState<{ x: number; y: number } | null>(null);
  const hasLabel = label.length > 0;
  const effectivelyDisabled = disabled || !hasLabel;

  const { visibility, isMounted, show, hide, hideImmediately } = useTooltipState({
    delayMs,
    disabled: effectivelyDisabled,
  });
  const tooltipDescriptionId = isMounted ? id : undefined;
  const triggerChild = renderTooltipTriggerChild(children, tooltipDescriptionId);

  // Recompute position whenever we become visible or resize/scroll.
  useLayoutEffect(() => {
    if (!isMounted) return;
    const trigger = triggerRef.current;
    const tooltip = tooltipRef.current;
    if (!trigger || !tooltip) return;
    const triggerRect = trigger.getBoundingClientRect();
    const tooltipRect = tooltip.getBoundingClientRect();
    const next = computeTooltipPosition(
      {
        top: triggerRect.top,
        left: triggerRect.left,
        width: triggerRect.width,
        height: triggerRect.height,
      },
      { width: tooltipRect.width, height: tooltipRect.height },
      { width: window.innerWidth, height: window.innerHeight },
      side,
      sideOffset,
    );
    setCoords(next);
  }, [isMounted, side, sideOffset, visibility]);

  // Hide on scroll / resize / Escape — any layout shift or escape key
  // invalidates the current pointer target, and we don't re-chase it.
  useEffect(() => {
    if (!isMounted) return;
    return installTooltipDismissRuntime({
      addWindowScrollListener: typeof window === 'undefined'
        ? null
        : (listener) => {
            window.addEventListener('scroll', listener, { capture: true, passive: true });
            return () => window.removeEventListener('scroll', listener, true);
          },
      addWindowResizeListener: typeof window === 'undefined'
        ? null
        : (listener) => {
            window.addEventListener('resize', listener);
            return () => window.removeEventListener('resize', listener);
          },
      addWindowKeydownListener: typeof window === 'undefined'
        ? null
        : (listener) => {
            window.addEventListener('keydown', listener);
            return () => window.removeEventListener('keydown', listener);
          },
      onDismiss: hideImmediately,
    });
  }, [hideImmediately, isMounted]);

  // ModalShell broadcasts `lorvex:close-all-tooltips` when a modal
  // opens so the tooltip layer (`--z-tooltip: 90`) doesn't paint over
  // the modal layer (`--z-modal: 60`). Without this, an already-open
  // tooltip on the modal's launching trigger lingers above the dialog
  // body until the user moves the pointer.
  useEffect(() => {
    if (!isMounted) return;
    if (typeof window === 'undefined') return;
    const handler = () => hideImmediately();
    window.addEventListener('lorvex:close-all-tooltips', handler);
    return () => window.removeEventListener('lorvex:close-all-tooltips', handler);
  }, [hideImmediately, isMounted]);

  if (effectivelyDisabled) {
    return <>{children}</>;
  }

  return (
    <>
      {/* `contents` keeps the wrapper out of the flex/grid layout flow,
          so the trigger's own styling (margins, flex-basis, etc.) is
          preserved exactly as if Tooltip weren't here. */}
      <span
        ref={triggerRef}
        className="contents"
        // Presentational wrapper: `display: contents` keeps the span
        // out of layout flow and the actual interactive element lives
        // inside as the trigger child. The mouse/focus listeners here
        // exist only to drive the hover-tooltip lifecycle; they don't
        // make the wrapper itself a control. Marking it `presentation`
        // tells AT (and jsx-a11y) to treat it as non-semantic chrome.
        role="presentation"
        onMouseEnter={show}
        onMouseLeave={hide}
        onFocus={show}
        onBlur={hide}
        onTouchStart={hideImmediately}
      >
        {triggerChild}
      </span>
      {isMounted ? (
        <OverlayPortal>
          <div
            ref={tooltipRef}
            role="tooltip"
            id={id}
            style={{
              position: 'fixed',
              top: coords?.y ?? 0,
              left: coords?.x ?? 0,
              pointerEvents: 'none',
              // Hide until we've measured at least once so the tooltip
              // doesn't flash at (0,0) before useLayoutEffect runs.
              visibility: coords ? 'visible' : 'hidden',
              // Use inline style (not dynamic Tailwind) so we can vary
              // the duration between open (120 ms) and closing (80 ms).
              transitionProperty: 'opacity',
              transitionDuration: visibility === 'closing' ? '80ms' : '120ms',
              transitionTimingFunction: 'ease-out',
            }}
            className={
              'z-[var(--z-tooltip)] max-w-xs rounded-r-control bg-surface-2 px-2 py-1 text-xs ' +
              'text-text-primary shadow-[var(--shadow-tooltip)] ring-1 ring-surface-3 ' +
              (visibility === 'open' ? 'opacity-100' : 'opacity-0')
            }
          >
            {label}
          </div>
        </OverlayPortal>
      ) : null}
    </>
  );
}
