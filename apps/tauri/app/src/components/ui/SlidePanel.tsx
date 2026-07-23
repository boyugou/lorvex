import { useEffect, useLayoutEffect, useRef, type ReactNode, type RefObject } from 'react';
import { trapTabFocusWithin } from '@/lib/focus/focusTrap';
import { prefersReducedMotion } from '@/lib/reducedMotion';
import { readActiveHTMLElement } from '@/lib/focus/useFocusRestore.runtime';
import {
  createBrowserSlidePanelTabTrapRuntimeDeps,
  installSlidePanelTabTrapRuntime,
} from './SlidePanel.runtime';
import {
  createHTMLElementFocusRestoreMachine,
  type FocusRestoreMachine,
} from '@/lib/focus/focusRestore.logic';

// ---------------------------------------------------------------------------
// Component
// ---------------------------------------------------------------------------

interface SlidePanelProps {
  /** Whether the panel is visible. */
  open: boolean;
  /** Contents of the panel. */
  children: ReactNode;
  /** Extra className applied to the outer `<aside>`. */
  className?: string;
  /** Accessible name for the complementary region. */
  ariaLabel?: string;
  /**
   * Optional ref to the element that should receive focus when the
   * panel opens. If omitted, the panel itself is focused (it has
   * `tabIndex={-1}`).
   */
  initialFocusRef?: RefObject<HTMLElement | null>;
}

/**
 * Wrapper that adds enter/exit slide animation for conditionally rendered
 * panels, plus side-panel a11y semantics:
 *
 * - Renders a `<aside role="complementary" aria-label>` region (NOT a
 *   modal -- the panel intentionally coexists with the background list
 *   and must not steal background clicks). We deliberately do NOT set
 *   `aria-modal="true"`.
 *
 * - On open: captures the current active element as a restore target, then
 *   focuses `initialFocusRef.current` if provided, otherwise focuses the
 *   panel itself. The panel is `tabIndex={-1}` so it's programmatically
 *   focusable.
 *
 * - On close (or unmount while open): restores focus to the snapshot,
 *   but only if the snapshot is still in the DOM and visible. A detached
 *   node or a hidden one would silently drop focus to `<body>`, which is
 *   a confusing state for keyboard users.
 *
 * - While open: traps Tab/Shift-Tab within the panel via a document
 *   keydown listener. Unlike ModalShell this is scoped by proximity to
 *   the panel -- keys only trap when the current activeElement is inside
 *   the panel; when focus is out in the background list (which is
 *   allowed for a side panel) normal tab order applies.
 *
 * SlidePanel does not own dismiss gestures because it intentionally
 * coexists with the background list; parent surfaces close it through
 * their own task-detail chrome and shortcut handling.
 *
 * Uses CSS @starting-style + transition-behavior: allow-discrete for
 * pure-CSS enter/exit animations -- no JS state management needed for
 * the animation itself.
 */
export function SlidePanel({
  open,
  children,
  className = '',
  ariaLabel,
  initialFocusRef,
}: SlidePanelProps) {
  const panelRef = useRef<HTMLElement | null>(null);

  // Live ref to initialFocusRef so the open effect (which depends only
  // on `open`) always reads the latest target. Consumers frequently pass
  // a ref whose `.current` only becomes defined after the panel's
  // children mount in the same commit -- the useLayoutEffect below runs
  // after children mount, so .current is available by then.
  const initialFocusRefRef = useRef(initialFocusRef);
  initialFocusRefRef.current = initialFocusRef;

  // Restore machine is stable for the lifetime of the component.
  const machineRef = useRef<FocusRestoreMachine<HTMLElement> | null>(null);
  if (machineRef.current === null) {
    machineRef.current = createHTMLElementFocusRestoreMachine();
  }

  // Track whether we've applied the "open" side effects so we can
  // symmetrically run the "close" restoration exactly once, whether the
  // panel transitions to closed or unmounts entirely.
  const openedRef = useRef(false);

  // Open/close side effects: snapshot on open, restore on close.
  // useLayoutEffect so the focus transition happens synchronously with
  // the render that shows/hides the panel -- avoids a visible frame
  // where the panel is on screen but focus is still in the background.
  //
  // Move focus after the slide-in transition completes (via
  // `transitionend`), so VoiceOver's focus halo and the browser's
  // focus-visible outline park cleanly at the panel's final resting
  // position instead of drifting across the screen alongside the
  // translating panel. A fallback timer matching the CSS duration
  // covers the cases where `transitionend` never arrives (the panel
  // unmounts mid-transition, or the user backgrounds the tab and
  // the transition is skipped). Under `prefers-reduced-motion`, the
  // CSS transition collapses to ~0ms — focus synchronously to
  // avoid a single-frame delay that AT users would notice as
  // keyboard lag.
  useLayoutEffect(() => {
    const machine = machineRef.current!;
    if (open && !openedRef.current) {
      openedRef.current = true;
      machine.open(readActiveHTMLElement());
      const target = initialFocusRefRef.current?.current ?? panelRef.current;
      if (!target || typeof target.focus !== 'function') return;

      const reducedMotion = prefersReducedMotion(typeof window !== 'undefined' ? window : undefined);
      const panel = panelRef.current;
      if (reducedMotion || !panel) {
        target.focus();
        return;
      }

      // Wait for the panel's own transitionend (transform/opacity).
      // Children's transitionend bubbles up too, so filter to the panel
      // itself. Fallback timer matches the 150ms CSS duration in
      // index.css `slide-panel` utility, plus a small buffer.
      //
      // the prior implementation registered the
      // transitionend listener and the fallback timeout but returned
      // no cleanup, so a parent unmount or fast `open` flip leaked
      // both — the listener stayed bound to the (already-orphaned)
      // panel node, and the timer fired into a closure that called
      // `focus()` on a possibly-detached element. Track cancellation
      // through a `cancelled` flag (so the deferred `focus()` is a
      // true no-op if the effect tore down) and explicitly remove the
      // listener + clear the timeout in the cleanup return.
      const SLIDE_PANEL_TRANSITION_MS = 150;
      const FALLBACK_BUFFER_MS = 30;
      let done = false;
      let cancelled = false;
      const finish = () => {
        if (done) return;
        done = true;
        panel.removeEventListener('transitionend', onTransitionEnd);
        clearTimeout(fallback);
        if (cancelled) return;
        // Re-check that the open commit is still in effect — a fast
        // open->close toggle could land here after the close path ran.
        if (openedRef.current && typeof target.focus === 'function') {
          target.focus();
        }
      };
      const onTransitionEnd = (event: TransitionEvent) => {
        if (event.target !== panel) return;
        if (event.propertyName !== 'transform' && event.propertyName !== 'opacity') return;
        finish();
      };
      panel.addEventListener('transitionend', onTransitionEnd);
      const fallback = setTimeout(finish, SLIDE_PANEL_TRANSITION_MS + FALLBACK_BUFFER_MS);
      return () => {
        cancelled = true;
        if (!done) {
          done = true;
          panel.removeEventListener('transitionend', onTransitionEnd);
          clearTimeout(fallback);
        }
      };
    } else if (!open && openedRef.current) {
      openedRef.current = false;
      machine.close();
    }
    return undefined;
  }, [open]);

  // On unmount while still open: restore focus. React cleans up the
  // layout-effect above for us, but only when `open` or the component
  // itself changes. A parent that conditionally renders SlidePanel --
  // `{selectedTaskId !== null && <SlidePanel open ...>}` -- unmounts
  // the whole component without ever flipping `open` to false, so we
  // wouldn't otherwise run the restore.
  useEffect(() => {
    return () => {
      if (openedRef.current) {
        openedRef.current = false;
        machineRef.current?.close();
      }
    };
  }, []);

  // Tab trap: only engage when focus is inside the panel. If the user
  // has intentionally moved focus back to the background list, we must
  // let normal tab order work -- this isn't a modal.
  useEffect(() => {
    if (!open) return;
    return installSlidePanelTabTrapRuntime(
      createBrowserSlidePanelTabTrapRuntimeDeps({
        getPanel: () => panelRef.current,
        trapTabFocus: trapTabFocusWithin,
      }),
    );
  }, [open]);

  return (
    <aside
      ref={panelRef}
      role="complementary"
      aria-label={ariaLabel}
      tabIndex={-1}
      className={`slide-panel outline-hidden ${className}`}
      hidden={!open || undefined}
    >
      {children}
    </aside>
  );
}
