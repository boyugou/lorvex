import { useCallback, useEffect, useRef } from 'react';
import { trapTabFocusWithin } from '@/lib/focus/focusTrap';
import {
  createHTMLElementFocusRestoreMachine,
  type FocusRestoreMachine,
} from '@/lib/focus/focusRestore.logic';
import { markEscapeEventHandled } from '@/lib/focus/escapeKeyOwnership';
import { readActiveHTMLElement } from '@/lib/focus/useFocusRestore.runtime';
import { OverlayPortal } from './OverlayPortal';

// ---------------------------------------------------------------------------
// Module-level modal-escape stack
// ---------------------------------------------------------------------------
//
// When two ModalShells are open simultaneously (e.g. a ConfirmDialog
// opened from inside a CommandPalette action), the naive "each modal
// registers its own document keydown listener" approach hands Escape
// to the WRONG modal — specifically, the modal that was OPENED FIRST,
// because `document.addEventListener` fires listeners in registration
// order and the first listener calls `stopImmediatePropagation()`.
//
// The fix is to install exactly ONE global keydown listener and route
// Escape to whichever modal is currently topmost of the stack. Each
// `ModalShell` effect pushes its `onClose` onto the stack when it
// opens and removes it on unmount / close; the topmost entry wins.
//
// This preserves existing behavior for the common single-modal case
// while correctly handling stacked modals.
const modalEscapeStack: Array<() => void> = [];
let globalModalEscapeListenerInstalled = false;
type ModalKeydownListenerTarget = Pick<Document, 'addEventListener'>;

export function scheduleGlobalModalEscapeClose(
  event: Pick<KeyboardEvent, 'defaultPrevented' | 'isComposing' | 'key'> & object,
  onClose: () => void,
  schedule: (cb: () => void) => void = queueMicrotask,
): boolean {
  if (event.key !== 'Escape' || event.isComposing) return false;
  markEscapeEventHandled(event);
  schedule(() => {
    if (!event.defaultPrevented) {
      onClose();
    }
  });
  return true;
}

function handleGlobalModalEscape(e: KeyboardEvent): void {
  const top = modalEscapeStack[modalEscapeStack.length - 1];
  if (!top) return;
  scheduleGlobalModalEscapeClose(e, top);
}

export function registerGlobalModalEscapeListener(target: ModalKeydownListenerTarget): void {
  target.addEventListener('keydown', handleGlobalModalEscape, true);
}

function ensureGlobalModalEscapeListener(): void {
  if (globalModalEscapeListenerInstalled) return;
  // Capture phase so we fire before any panel-level handler that might
  // eat the Escape for its own purposes (the panel's own onKeyDown
  // runs in bubble phase and must remain free to add sub-scoped
  // behavior like "Escape cancels inline edit" inside the panel).
  registerGlobalModalEscapeListener(document);
  globalModalEscapeListenerInstalled = true;
}

/**
 * Push an Escape handler onto the same module-level stack ModalShell uses.
 * Returned function pops the handler off the stack.
 *
 * Use this for stacked overlays that don't render through ModalShell (e.g.
 * the desktop DatePicker popover, anchored to a trigger inside another
 * modal). Routing through the same stack guarantees that Escape closes
 * exactly the topmost overlay — without this, parallel document listeners
 * would either steal Escape from ModalShell or leak it through to the
 * outer modal, depending on registration order.
 */
export function pushModalEscapeHandler(onEscape: () => void): () => void {
  ensureGlobalModalEscapeListener();
  modalEscapeStack.push(onEscape);
  return () => {
    const idx = modalEscapeStack.lastIndexOf(onEscape);
    if (idx !== -1) {
      modalEscapeStack.splice(idx, 1);
    }
  };
}

const modalTabStack: Array<React.RefObject<HTMLDivElement | null>> = [];
let globalModalTabListenerInstalled = false;
let globalModalFocusRecoveryListenerInstalled = false;

export function collectModalTabScopeRootsFromBodyChildren(
  bodyChildren: Iterable<Element>,
  overlayRoot: Element | null,
): HTMLElement[] {
  const roots: HTMLElement[] = [];
  if (overlayRoot instanceof HTMLElement && !overlayRoot.hasAttribute('inert') && overlayRoot.getAttribute('aria-hidden') !== 'true') {
    roots.push(overlayRoot);
  }
  for (const child of bodyChildren) {
    if (!(child instanceof HTMLElement)) continue;
    if (child === overlayRoot) continue;
    if (child.hasAttribute('inert')) continue;
    if (child.getAttribute('aria-hidden') === 'true') continue;
    roots.push(child);
  }
  return roots;
}

function getModalTabScopeRoots(panel: HTMLDivElement | null): HTMLElement[] {
  const overlayRoot = findBodyChildAncestor(panel);
  return collectModalTabScopeRootsFromBodyChildren(document.body.children, overlayRoot);
}

function handleGlobalModalTab(e: KeyboardEvent): void {
  if (e.key !== 'Tab' || e.defaultPrevented) return;
  const top = modalTabStack[modalTabStack.length - 1];
  if (!top?.current) return;
  trapTabFocusWithin(top.current, e, {
    extraRoots: getModalTabScopeRoots(top.current),
  });
}

export function registerGlobalModalTabListener(target: ModalKeydownListenerTarget): void {
  target.addEventListener('keydown', handleGlobalModalTab, true);
}

function ensureGlobalModalTabListener(): void {
  if (globalModalTabListenerInstalled) return;
  registerGlobalModalTabListener(document);
  globalModalTabListenerInstalled = true;
}

export function recoverTopModalFocusWhenBodyActive(
  activeElement: Element | null,
  topPanel: Pick<HTMLElement, 'focus'> | null,
): boolean {
  if (activeElement !== document.body || !topPanel) return false;
  topPanel.focus();
  return true;
}

function handleGlobalModalFocusIn(): void {
  const top = modalTabStack[modalTabStack.length - 1];
  recoverTopModalFocusWhenBodyActive(document.activeElement, top?.current ?? null);
}

function ensureGlobalModalFocusRecoveryListener(): void {
  if (globalModalFocusRecoveryListenerInstalled) return;
  document.addEventListener('focusin', handleGlobalModalFocusIn);
  globalModalFocusRecoveryListenerInstalled = true;
}

export function shouldDismissModalFromBackdropClick(
  target: EventTarget | null,
  panel: Pick<Node, 'contains'> | null,
  backdropDismiss: boolean,
): boolean {
  if (!backdropDismiss) return false;
  if (!target || !panel) return true;
  return !panel.contains(target as Node);
}

// ---------------------------------------------------------------------------
// Global modal inert stack
// ---------------------------------------------------------------------------
//
// Even with the Escape stack and the Tab trap, a screen-reader user can
// still navigate OUT of the modal: VoiceOver's VO+arrow keys, the rotor,
// and heading-jump commands all move SR focus without firing Tab, so
// they bypass the keydown-phase trap. The fix is to hide background
// content from the accessibility tree entirely while a modal is open by
// applying `inert` (and `aria-hidden="true"` as a fallback for user
// agents that ignore `inert` on SR nav) to every direct child of
// `<body>` that is NOT the overlay portal container hosting the
// topmost modal.
//
// Stacked modals complicate this: naively toggling on every push/pop
// would double-mark elements, or worse, clear the attribute while a
// lower modal is still open. We mirror the Escape / Tab stacks — push
// each ModalShell's panel ref onto `modalInertStack`, but only apply
// DOM changes when the TOPMOST entry changes. When a second modal
// opens on top of the first, no DOM change is needed: the body's
// background siblings were already marked when the first modal opened,
// and the first modal's overlay (which hosts the second modal via the
// same OverlayPortal) stays non-inert. Symmetrically, closing the top
// modal only restores attributes when the stack empties.
const modalInertStack: Array<React.RefObject<HTMLDivElement | null>> = [];

// Elements we marked as inert/aria-hidden, along with the attribute
// state we saw before marking so cleanup restores exactly what was
// there. Using a Map (not WeakMap) because we iterate on cleanup.
const markedBackgroundElements = new Map<
  Element,
  { hadInert: boolean; priorAriaHidden: string | null }
>();

function findBodyChildAncestor(node: Element | null): Element | null {
  let current: Element | null = node;
  while (current && current.parentElement !== document.body) {
    current = current.parentElement;
  }
  return current;
}

function applyBackgroundInert(panel: HTMLElement | null): void {
  const overlayRoot = findBodyChildAncestor(panel);
  const bodyChildren = Array.from(document.body.children);
  for (const child of bodyChildren) {
    if (child === overlayRoot) continue;
    // Skip script / style / link tags — they're not focusable and
    // marking them aria-hidden is meaningless noise.
    const tag = child.tagName;
    if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'LINK') continue;
    const el = child as HTMLElement;
    const hadInert = el.hasAttribute('inert');
    const priorAriaHidden = el.getAttribute('aria-hidden');
    markedBackgroundElements.set(el, { hadInert, priorAriaHidden });
    if (!hadInert) el.setAttribute('inert', '');
    el.setAttribute('aria-hidden', 'true');
  }
}

function clearBackgroundInert(): void {
  for (const [el, prior] of markedBackgroundElements) {
    if (!prior.hadInert) el.removeAttribute('inert');
    if (prior.priorAriaHidden === null) {
      el.removeAttribute('aria-hidden');
    } else {
      el.setAttribute('aria-hidden', prior.priorAriaHidden);
    }
  }
  markedBackgroundElements.clear();
}

function syncBackgroundInertToTopModal(): void {
  clearBackgroundInert();
  const top = modalInertStack[modalInertStack.length - 1];
  if (top?.current) {
    applyBackgroundInert(top.current);
  }
}

interface ModalShellProps {
  /** Whether the modal is open. When false, renders nothing. */
  open: boolean;
  /** Called when the user dismisses (Escape, backdrop click). */
  onClose: () => void;
  children: React.ReactNode;
  /** Extra className applied to the panel container (the dialog element). */
  panelClassName?: string;
  /** Whether clicking the backdrop dismisses the modal. Default true. */
  backdropDismiss?: boolean;
  /** Extra className for the fixed outer wrapper. */
  className?: string;
  /** z-index utility class. Default "z-[var(--z-modal)]". */
  zIndex?: string;
  /** Flex alignment for the panel within the viewport. Default "items-center justify-center". */
  align?: string;
  /**
   * Backdrop class. Defaults to `bg-[var(--color-overlay)]` so
   * picker overlays (Due/Duration/Recurrence/List/DatePicker) that
   * mount ModalShell directly inherit the per-theme overlay token
   * — a hardcoded `bg-black/30` would render the same flat black
   * wash under dark/sepia themes.
   */
  backdropClassName?: string;
  /** aria-label for the dialog. */
  ariaLabel?: string;
  /** aria-labelledby for the dialog — takes precedence over ariaLabel if set. */
  ariaLabelledBy?: string;
  /**
   * `aria-describedby` for the dialog body. Lets consumers
   * point screen readers at the descriptive copy (e.g. the message in
   * a confirm prompt) so SR users hear "Title… Message… Cancel /
   * Confirm" instead of just the title and the buttons.
   */
  ariaDescribedBy?: string;
  /**
   * Additional keydown handler on the panel. Runs BEFORE the built-in
   * focus-trap handler. If the event is Escape, ModalShell handles it via
   * its own global listener — you do not need to handle Escape here.
   */
  onPanelKeyDown?: (e: React.KeyboardEvent) => void;
  /**
   * If false, ModalShell will NOT auto-focus the dialog panel on mount.
   * Use this when the consumer focuses a specific child (e.g. an input).
   * Default true.
   */
  autoFocus?: boolean;
  /**
   * explicit focus target. When provided AND `autoFocus`
   * is true, ModalShell focuses this element on mount instead of the
   * dialog panel itself. Lets consumers (QuickCapture, future inline-
   * edit modals) hand off focus to a specific child input without
   * having to set `autoFocus={false}` and ship their own
   * focus-on-mount effect — a per-consumer effect is one of the
   * easiest places to drift on deps. When the ref is unset at
   * mount, ModalShell falls back to focusing the panel so focus
   * never leaks to `<body>`.
   *
   * Typed as `{ current: { focus(): void } | null }` (rather than
   * `RefObject<HTMLElement>`) so consumers can hand off any of
   * `RefObject<HTMLInputElement>`, `<HTMLTextAreaElement>`,
   * `<HTMLButtonElement>` etc. without `as` casting — `useRef` returns
   * an invariant RefObject, so a more specific element type isn't
   * assignable to `RefObject<HTMLElement>`.
   */
  focusTarget?: { current: { focus: () => void } | null };
  /**
   * Ref callback exposed so consumers can access the panel DOM node
   * (e.g. to pass to `trapTabFocusWithin` in their own keydown handler).
   */
  panelRef?: React.RefCallback<HTMLDivElement> | React.RefObject<HTMLDivElement | null>;
  /**
   * explicit trigger element captured synchronously by
   * the consumer at the moment they chose to open the modal. When
   * provided, it takes precedence over ModalShell's own at-mount
   * capture of `document.activeElement`. Use this when the imperative
   * call path (e.g. \`confirm()\`) has a better signal than the
   * render-scheduled mount — a context menu that closed and re-focused
   * its launcher button would otherwise leave \`document.activeElement\`
   * as \`<body>\` at the exact microtask ModalShell mounts, silently
   * dropping focus on close.
   */
  triggerElement?: HTMLElement | null;
}

/**
 * Unified modal shell providing:
 * - Portal to document.body
 * - Backdrop (configurable opacity, click-to-dismiss)
 * - Escape key dismiss (global listener — works even if panel lacks focus)
 * - Tab focus trap (via `trapTabFocusWithin`)
 * - Focus restore on close (via `useFocusRestore`)
 *
 * Consumers supply children (the panel content) and configure via props.
 */
export function ModalShell({
  open,
  onClose,
  children,
  panelClassName = '',
  backdropDismiss = true,
  className = '',
  zIndex = 'z-[var(--z-modal)]',
  align = 'items-center justify-center',
  backdropClassName = 'bg-[var(--color-overlay)]',
  ariaLabel,
  ariaLabelledBy,
  ariaDescribedBy,
  onPanelKeyDown,
  autoFocus = true,
  panelRef: externalRef,
  triggerElement,
  focusTarget,
}: ModalShellProps) {
  const focusRestoreMachineRef = useRef<FocusRestoreMachine<HTMLElement> | null>(null);
  if (focusRestoreMachineRef.current === null) {
    focusRestoreMachineRef.current = createHTMLElementFocusRestoreMachine();
  }
  const focusRestoreMachine = focusRestoreMachineRef.current;
  const triggerRef = useRef(triggerElement);
  triggerRef.current = triggerElement;

  useEffect(() => {
    if (open) {
      // prefer the explicit \`triggerElement\` captured by
      // the imperative caller at invocation time. Falls back to the
      // at-mount \`document.activeElement\` only when the caller didn't
      // (or couldn't) capture synchronously.
      focusRestoreMachine.open(
        triggerRef.current ?? readActiveHTMLElement(),
      );
      // Tooltips sit on the `--z-tooltip` layer (90), one rung above
      // `--z-modal` (60). Without this broadcast a tooltip that was
      // already visible on the modal's launching trigger paints over
      // the dialog body until the user mouses away. Every Tooltip
      // listens for this event and dismisses its open instance.
      if (typeof window !== 'undefined') {
        window.dispatchEvent(new CustomEvent('lorvex:close-all-tooltips'));
      }
    }
    return () => {
      if (!open) return;
      focusRestoreMachine.close();
    };
    // focusRestoreMachine is a singleton stored via useRef and
    // initialized once on mount; its identity never changes.
  }, [open, focusRestoreMachine]);

  const internalRef = useRef<HTMLDivElement>(null);

  // Merge the internal ref with any external ref
  const setRef = useCallback(
    (node: HTMLDivElement | null) => {
      (internalRef as React.MutableRefObject<HTMLDivElement | null>).current = node;
      if (typeof externalRef === 'function') {
        externalRef(node);
      } else if (externalRef) {
        (externalRef as React.MutableRefObject<HTMLDivElement | null>).current = node;
      }
    },
    [externalRef],
  );

  // Auto-focus the dialog panel so keyboard events are captured. When
  // the consumer supplies a `focusTarget` ref pointing at a specific
  // child, prefer that — falls back to the panel if the ref hasn't
  // resolved yet (so we never leak focus to `<body>`).
  useEffect(() => {
    if (!open || !autoFocus) return;
    const target = focusTarget?.current ?? internalRef.current;
    target?.focus();
  }, [open, autoFocus, focusTarget]);

  // Escape dismiss: route through the module-level modal stack so
  // that when multiple modals are open at once, only the topmost one
  // receives the Escape. See `modalEscapeStack` above.
  useEffect(() => {
    if (!open) return;
    ensureGlobalModalEscapeListener();
    modalEscapeStack.push(onClose);
    return () => {
      const idx = modalEscapeStack.lastIndexOf(onClose);
      if (idx !== -1) {
        modalEscapeStack.splice(idx, 1);
      }
    };
  }, [open, onClose]);

  // Tab trap:. Register the panel ref on a global stack
  // so the document-level Tab listener can trap focus even when it
  // enters a portaled child outside the panel's DOM subtree.
  useEffect(() => {
    if (!open) return;
    ensureGlobalModalTabListener();
    ensureGlobalModalFocusRecoveryListener();
    modalTabStack.push(internalRef);
    return () => {
      const idx = modalTabStack.lastIndexOf(internalRef);
      if (idx !== -1) {
        modalTabStack.splice(idx, 1);
      }
    };
  }, [open]);

  // hide background content from the accessibility tree
  // while the modal is open. Only the TOPMOST modal owns the DOM
  // attribute toggle — stacked modals push onto the stack without
  // re-applying, so a second modal opening on top of the first doesn't
  // touch attributes already correctly set by the first.
  useEffect(() => {
    if (!open) return;
    modalInertStack.push(internalRef);
    syncBackgroundInertToTopModal();
    return () => {
      const idx = modalInertStack.lastIndexOf(internalRef);
      if (idx !== -1) modalInertStack.splice(idx, 1);
      syncBackgroundInertToTopModal();
    };
  }, [open]);

  const handleBackdropClick = useCallback(
    (e: React.MouseEvent) => {
      if (shouldDismissModalFromBackdropClick(e.target, internalRef.current, backdropDismiss)) {
        onClose();
      }
    },
    [backdropDismiss, onClose],
  );

  const handlePanelKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      // Let consumer handle first (arrows, Enter, etc.). The Tab trap
      // now runs from the document-level listener (see
      // `modalTabStack`) so it covers portaled children too.
      onPanelKeyDown?.(e);
    },
    [onPanelKeyDown],
  );

  if (!open) return null;

  return (
    <OverlayPortal>
      <div
        className={`fixed inset-0 ${zIndex} flex ${align} ${className}`}
        onClick={handleBackdropClick}
        role="presentation"
      >
        <div className={`absolute inset-0 ${backdropClassName}`} />
        <div
          ref={setRef}
          tabIndex={-1}
          className={`relative outline-hidden ${panelClassName}`}
          role="dialog"
          aria-modal="true"
          aria-label={ariaLabelledBy ? undefined : ariaLabel}
          aria-labelledby={ariaLabelledBy}
          aria-describedby={ariaDescribedBy}
          onKeyDown={handlePanelKeyDown}
        >
          {children}
        </div>
      </div>
    </OverlayPortal>
  );
}
