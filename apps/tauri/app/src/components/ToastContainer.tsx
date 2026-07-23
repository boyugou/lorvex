import { useEffect, useRef, useState, type ReactNode } from 'react';
import { useI18n } from '../lib/i18n';
import { getRuntimeProfile } from '../lib/platform/platform';
import {
  useToasts,
  dismissToast,
  removeToast,
  pauseToastDismiss,
  resumeToastDismiss,
  type ToastItem,
} from '../lib/notifications/toast';
import { confirm } from '../lib/dialogs/confirm';
import { reportClientError } from '../lib/errors/errorLogging';
import { useReducedMotion } from '../lib/reducedMotion';
import { CheckIcon, XIcon } from './ui/icons';
import { isAssertiveToast } from './ToastContainer.logic';

const RUNTIME_PROFILE = getRuntimeProfile();
// on mobile the bottom tab bar is `h-14` (56 px) plus the
// home-indicator safe-area inset. Stacking the toast above both keeps
// error announcements from landing on top of the nav.
// also lift above the soft keyboard when it's open
// (`--kb-inset` is set by `useVisualViewportInset`).
const TOAST_BOTTOM_CLASS =
  RUNTIME_PROFILE.runtimeClass === 'mobile'
    ? 'bottom-[calc(3.5rem+env(safe-area-inset-bottom,0px)+var(--kb-inset,0px)+0.5rem)]'
    : 'bottom-6';
// The close button's hit-target
// diverges by runtime so each input device gets the right minimum.
// Mobile ≥44×44 (WCAG 2.2 touch minimum), desktop ≥24×24 (WCAG 2.1
// pointer minimum — desktop pointers drift and the old 16×16 square
// was missable on trackpads). The visible X glyph
// (now `w-3.5 h-3.5` / 14 px) matches the success/error message icons
// so the close affordance reads at the same weight on both runtimes
// and the previous 24×24 box no longer carries a 6 px halo of empty
// padding around a 12 px glyph that scanned as decoration rather than
// a button.
const TOAST_CLOSE_BTN_CLASS =
  RUNTIME_PROFILE.runtimeClass === 'mobile'
    ? 'shrink-0 ms-1 min-tap flex items-center justify-center rounded-r-control text-text-muted/70 hover:text-text-primary transition-colors focus-ring-soft'
    : 'shrink-0 ms-1 min-w-6 min-h-6 flex items-center justify-center rounded-r-control text-text-muted/70 hover:text-text-primary transition-colors focus-ring-soft';

const TOAST_ACTION_BTN_CLASS =
  RUNTIME_PROFILE.runtimeClass === 'mobile'
    ? 'relative shrink-0 inline-flex min-tap max-w-[7rem] flex-wrap items-center justify-center gap-1.5 mt-0.5 px-2 text-accent text-xs font-medium leading-4 text-center break-words whitespace-normal hover:text-accent/80 disabled:hover:text-accent transition-colors ms-1 rounded-r-control focus-ring-soft'
    : 'relative shrink-0 inline-flex min-w-6 min-h-6 max-w-[10rem] flex-wrap items-center justify-center gap-1.5 mt-0.5 px-1 text-accent text-xs font-medium leading-4 text-center break-words whitespace-normal hover:text-accent/80 disabled:hover:text-accent transition-colors ms-2 rounded-r-control focus-ring-soft';

const TYPE_STYLES: Record<ToastItem['type'], string> = {
  success: 'bg-surface-2 border-success/30 text-text-primary',
  error:   'bg-surface-2 border-danger/40 text-text-primary',
  info:    'bg-surface-2 border-surface-3 text-text-primary',
  // warning uses an amber/yellow border so partial-success
  // outcomes read as distinct from total failure (red) and
  // confirmation (green). Keeps the same `bg-surface-2` chrome so
  // the rest of the toast vocabulary stays consistent.
  // warning amber sits closer to the surface-2 chroma than
  // danger red on light themes, so the border at /40 read almost
  // as the unstyled `border-card`. /60 lifts the amber stroke clear
  // of the chrome on light themes while staying within the same
  // band as `border-danger/40` on dark — both vary by ~the same
  // perceptual delta against their respective surfaces.
  warning: 'bg-surface-2 border-warning/60 text-text-primary',
};

const ICON: Record<ToastItem['type'], () => ReactNode> = {
  success: () => <CheckIcon className="w-3.5 h-3.5" />,
  error:   () => <XIcon className="w-3.5 h-3.5" />,
  info:    () => <span className="text-xs leading-none">{'\u00B7'}</span>,
  // Bang glyph reads as "attention" without escalating to the X-mark
  // used for hard errors.
  warning: () => <span className="text-xs leading-none font-semibold">!</span>,
};

const ICON_COLOR: Record<ToastItem['type'], string> = {
  success: 'text-success',
  error:   'text-danger',
  info:    'text-text-muted',
  warning: 'text-warning',
};

const MESSAGE_COLOR: Record<ToastItem['type'], string> = {
  success: 'text-text-primary',
  error: 'text-text-primary',
  info: 'text-text-secondary',
  warning: 'text-text-primary',
};

// Number of visible toasts at which the "Dismiss all" affordance appears.
// Below this we keep the rail clean (each toast still has its own × button);
// above this the user is buried in stacked notifications and benefits from
// a single sweep clear.
const DISMISS_ALL_THRESHOLD = 3;

export default function ToastContainer() {
  const { t: tr, format } = useI18n();
  const toasts = useToasts();

  // TC2 +: ONE roving live region per priority (polite for
  // success/info, assertive for error AND warning) lives on the
  // container. Per-toast live regions had each toast carry its own
  // role="status"/role="alert" wrappers — when a toast was dismissed
  // and re-announced, the container's whole live-region subtree was
  // rewritten and AT re-spoke every visible message. Hoisting the
  // regions to the container and writing only the latest message
  // text per priority means each new toast announces exactly once.
  //
  // Warning toasts carry partial-failure outcomes —
  // "rescheduled 7 of 12, 5 failed" — that the user must hear
  // immediately, not after their current speech finishes (polite
  // queues until idle and can lag by tens of seconds in chatty
  // screens). They route to the assertive region alongside errors.
  //
  // Track the most recently-seen toast id per priority and only
  // update the announced text when the id changes — that way a
  // dismiss-induced re-render doesn't re-announce the surviving
  // messages.
  const lastAssertiveIdRef = useRef<string | null>(null);
  const lastPoliteIdRef = useRef<string | null>(null);
  const [assertiveAnnouncement, setAssertiveAnnouncement] = useState<string>('');
  const [politeAnnouncement, setPoliteAnnouncement] = useState<string>('');

  useEffect(() => {
    const visible = toasts.filter((toast) => !toast.dismissing);
    const newestAssertive = [...visible].reverse().find(isAssertiveToast);
    const newestPolite = [...visible].reverse().find((toast) => !isAssertiveToast(toast));

    if (newestAssertive && lastAssertiveIdRef.current !== newestAssertive.id) {
      lastAssertiveIdRef.current = newestAssertive.id;
      setAssertiveAnnouncement(newestAssertive.message);
    } else if (!newestAssertive && lastAssertiveIdRef.current !== null) {
      lastAssertiveIdRef.current = null;
      setAssertiveAnnouncement('');
    }

    if (newestPolite && lastPoliteIdRef.current !== newestPolite.id) {
      lastPoliteIdRef.current = newestPolite.id;
      setPoliteAnnouncement(newestPolite.message);
    } else if (!newestPolite && lastPoliteIdRef.current !== null) {
      lastPoliteIdRef.current = null;
      setPoliteAnnouncement('');
    }
  }, [toasts]);

  if (toasts.length === 0) return null;

  // Split into two sibling visual stacks so high-priority toasts read
  // as a separate priority lane (already true visually). Errors and
  // warnings share the priority stack — both convey
  // outcomes the user should attend to right now. Live-region
  // announcements happen at the container level via the regions
  // mounted at the very bottom of the tree.
  const priorityToasts = toasts.filter(isAssertiveToast);
  const otherToasts = toasts.filter((toast) => !isAssertiveToast(toast));
  const closeLabel = tr('common.close');
  const groupLabel = tr('toast.notification');

  const visibleCount = toasts.filter((toast) => !toast.dismissing).length;
  const visibleActionableCount = toasts.filter(
    (toast) => !toast.dismissing && toast.action,
  ).length;
  const showDismissAll = visibleCount >= DISMISS_ALL_THRESHOLD;
  const dismissAllLabel = format('toast.dismissAllCount', { count: visibleCount });

  const dismissAllToasts = () => {
    for (const toast of toasts) {
      if (!toast.dismissing) dismissToast(toast.id);
    }
  };

  const handleDismissAll = async () => {
    // when the visible stack contains any actionable toasts
    // (Undo / Retry / Open Settings), wholesale dismissal would silently
    // discard those affordances. Prompt the user with the count so they
    // see what they're about to lose.
    if (visibleActionableCount > 0) {
      const ok = await confirm({
        title: tr('toast.dismissAllConfirmTitle'),
        message: format('toast.dismissAllConfirmMessage', {
          count: visibleActionableCount,
        }),
        variant: 'danger',
        confirmLabel: tr('toast.dismissAllConfirmAction'),
      });
      if (!ok) return;
    }
    dismissAllToasts();
  };

  return (
    <div
      className={`fixed ${TOAST_BOTTOM_CLASS} inset-x-0 px-3 sm:px-4 flex flex-col items-center gap-2 z-[var(--z-toast)] pointer-events-none`}
      // Toast mounts no longer reflow descendants of the rail: each
      // toast's layout + paint stays inside the rail, so a freshly
      // pushed toast doesn't trigger CLS in the underlying page.
      style={{ contain: 'layout style' }}
    >
      {/* Stack-depth offset: the frontmost toast in the non-priority
          lane renders flush; each toast behind shifts up 4 px and
          shrinks slightly so the rail reads as a card deck. Depth is
          computed from the bottom of the lane (frontmost = 0).
          Priority toasts (error/warning) always render at depth 0 so
          critical outcomes (validation failures, partial-success
          summaries) stay legible at full size regardless of how many
          info/success toasts pile up underneath. The lane-separation
          already keeps the priority stack visually distinct; the
          deck-shrink would just trade severity legibility for
          ornamental rhythm. */}
      {otherToasts.map((toast, idx) => renderToast(toast, closeLabel, groupLabel, otherToasts.length - 1 - idx))}
      {priorityToasts.map((toast) => renderToast(toast, closeLabel, groupLabel, 0))}
      {showDismissAll && (
        <button
          type="button"
          onClick={() => { void handleDismissAll(); }}
          className="pointer-events-auto px-3 py-1 rounded-full bg-surface-2/90 border border-card text-text-muted hover:text-text-primary text-2xs font-medium shadow-[var(--shadow-popover)] focus-ring-soft transition-colors"
        >
          {dismissAllLabel}
        </button>
      )}
      {/* TC2: container-level roving live regions. The text is mirrored
          from the newest toast of each priority and only updates on
          id-change, so each toast announces exactly once even across
          dismiss/re-render cycles. Rendered after the visible stack
          so AT scans them in announcement order. */}
      <div role="status" aria-live="polite" aria-atomic="true" className="sr-only">
        {politeAnnouncement}
      </div>
      <div role="alert" aria-live="assertive" aria-atomic="true" className="sr-only">
        {assertiveAnnouncement}
      </div>
    </div>
  );
}

function renderToast(t: ToastItem, closeLabel: string, groupLabel: string, stackDepth: number) {
  return <ToastRow key={t.id} item={t} closeLabel={closeLabel} groupLabel={groupLabel} stackDepth={stackDepth} />;
}

function ToastRow({ item: t, closeLabel, groupLabel, stackDepth }: { item: ToastItem; closeLabel: string; groupLabel: string; stackDepth: number }) {
  const reducedMotion = useReducedMotion();
  // Hover-pause depletion bar. The bar drains left-to-right
  // over the toast's auto-dismiss duration; mouseenter pauses, both
  // the timer and the bar; mouseleave resumes. Toasts without a known
  // duration (legacy entries / tests) render no bar.
  const durationMs = t.durationMs;
  const [paused, setPaused] = useState(false);
  const [elapsedMs, setElapsedMs] = useState(0);
  const startRef = useRef<number>(Date.now());
  useEffect(() => {
    if (!durationMs || t.dismissing || paused) return;
    let rafId: number | null = null;
    const tick = () => {
      const now = Date.now();
      setElapsedMs(Math.min(durationMs, now - startRef.current));
      rafId = requestAnimationFrame(tick);
    };
    rafId = requestAnimationFrame(tick);
    return () => { if (rafId !== null) cancelAnimationFrame(rafId); };
  }, [durationMs, paused, t.dismissing]);
  const handleEnter = () => {
    if (!durationMs || t.dismissing) return;
    pauseToastDismiss(t.id);
    setPaused(true);
  };
  const handleLeave = () => {
    if (!durationMs || t.dismissing) return;
    // Reset the bar's start so the remaining ms drains visually from
    // the current depleted point — without this the bar would snap
    // back to zero elapsed on resume.
    const remainingMs = Math.max(0, durationMs - elapsedMs);
    startRef.current = Date.now() - (durationMs - remainingMs);
    resumeToastDismiss(t.id);
    setPaused(false);
  };
  const progressScale = durationMs
    ? Math.max(0, 1 - elapsedMs / durationMs)
    : 0;
  // outer wrapper owns the stack-depth transform so the
  // inner toast keeps its `toast-enter-exit` overshoot transform
  // composed cleanly against this offset. Depth 0 = frontmost
  // (flush); each layer behind shifts up 4 px and scales 0.98^depth.
  return (
    <div
      className="toast-stack-layer pointer-events-none"
      style={{ ['--toast-stack-depth' as 'top']: String(stackDepth) }}
    >
    <div
      // role="group" gives the visual toast a non-interactive landmark
      // role so the mouse/focus pause-on-hover handlers (handleEnter /
      // handleLeave) satisfy jsx-a11y/no-static-element-interactions
      // without duplicating the live-region announcements that the
      // sibling `role="status"` / `role="alert"` sr-only nodes already
      // own. The label is a short static word ("Notification") so AT
      // doesn't re-announce the full toast body on hover/focus — the
      // live-region siblings own the content announcement.
      role="group"
      aria-label={groupLabel}
      hidden={t.dismissing || undefined}
      onTransitionEnd={() => { if (t.dismissing) removeToast(t.id); }}
      onMouseEnter={handleEnter}
      onMouseLeave={handleLeave}
      onFocus={handleEnter}
      onBlur={handleLeave}
      className={`relative pointer-events-auto flex items-start gap-2.5 px-4 py-2.5 rounded-r-card border shadow-[var(--shadow-popover)] text-sm w-[min(calc(100vw_-_1.5rem),24rem)] toast-enter-exit overflow-hidden ${TYPE_STYLES[t.type]}`}
    >
      <span className={`shrink-0 flex items-center ${ICON_COLOR[t.type]} ${t.type === 'success' && !reducedMotion ? 'toast-success-pop' : ''}`} aria-hidden="true">
        {ICON[t.type]()}
      </span>
      <span className={`min-w-0 flex-1 break-words leading-5 ${MESSAGE_COLOR[t.type]}`}>
        {t.message}
      </span>
      {t.action && (
        <ToastActionButton toastId={t.id} action={t.action} />
      )}
      <button
        type="button"
        onClick={() => dismissToast(t.id)}
        className={TOAST_CLOSE_BTN_CLASS}
        aria-label={closeLabel}
      >
        <XIcon className="w-3.5 h-3.5" />
      </button>
      {durationMs ? (
        <span
          aria-hidden="true"
          className={`absolute bottom-0 inset-x-0 h-px origin-left ${ICON_COLOR[t.type]} bg-current opacity-60`}
          style={{
            transform: `scaleX(${progressScale})`,
            transition: reducedMotion ? 'none' : 'transform 80ms linear',
            // promote to its own compositor layer so the per-frame
            // transform update doesn't trigger a paint on the toast
            // body. Without this the bar drives a layout-thrash at
            // 60 fps on dark themes where the toast carries a shadow.
            willChange: reducedMotion ? undefined : 'transform',
          }}
        />
      ) : null}
    </div>
    </div>
  );
}

/**
 * Action button on a toast (Undo / Retry / Open Settings).
 *
 * Rendered as a separate component so it can own local pending state
 * for slow-IPC actions. Pre-extraction the click handler
 * dismissed the toast immediately and dispatched the action async,
 * which left the user with no signal during a 1-2 s undo round-trip
 * — they tapped Undo, the toast vanished, and nothing visibly happened
 * until the restored row reappeared.
 *
 * Behaviour:
 *   * Sync action (returns void) — dismiss the toast immediately.
 *   * Async action (returns Promise) — keep the toast visible, render
 *     an inline spinner in place of the action label, and dismiss the
 *     toast once the promise settles regardless of outcome. The
 *     button is disabled while pending so the action can't fire twice.
 *
 * The spinner mirrors `SubmitButton`'s primitive (14px ring + path,
 * `animate-spin` modulated by `prefers-reduced-motion`) so the visual
 * vocabulary is consistent across the app.
 */
function ToastActionButton({
  toastId,
  action,
}: {
  toastId: string;
  action: NonNullable<ToastItem['action']>;
}) {
  const [pending, setPending] = useState(false);
  const reducedMotion = useReducedMotion();
  const handleClick = () => {
    if (pending) return;
    let result: void | Promise<void>;
    try {
      result = action.onClick();
    } catch (err) {
      // Synchronous throw — rare, but surface diagnostics exactly
      // as the pre-extraction handler did so undo regressions stay
      // visible. Then dismiss the toast as a sync action would.
      reportClientError(
        'toast.clickAction',
        'Toast action threw (click path)',
        err,
      );
      dismissToast(toastId);
      return;
    }
    if (result && typeof (result as Promise<unknown>).then === 'function') {
      // Async action: keep the toast visible until settle, swap the
      // label for a spinner, and dismiss once the promise resolves
      // OR rejects. Rejections are surfaced through `reportClientError`
      // for parity with the keyboard shortcut path; user-facing copy
      // is owned by the action handler itself.
      setPending(true);
      void (result as Promise<unknown>)
        .catch((err) => {
          reportClientError(
            'toast.clickAction',
            'Toast action rejected (click path)',
            err,
            undefined,
            'warn',
          );
        })
        .finally(() => {
          setPending(false);
          dismissToast(toastId);
        });
    } else {
      // Synchronous action — dismiss immediately. (E.g. plain
      // `() => navigate(...)` callbacks.)
      dismissToast(toastId);
    }
  };
  return (
    <button
      type="button"
      onClick={handleClick}
      disabled={pending}
      aria-busy={pending || undefined}
      className={TOAST_ACTION_BTN_CLASS}
    >
      {pending && <ToastActionSpinner reducedMotion={reducedMotion} />}
      <span className={`min-w-0 flex-1 break-words ${pending ? 'opacity-70' : ''}`}>
        {action.label}
      </span>
    </button>
  );
}

/**
 * Inline 14px spinner that matches the `SubmitButton` primitive
 * (`app/src/components/ui/SubmitButton.tsx`). When reduced-motion is
 * on, render the static ring (no rotation) — the parent's `aria-busy`
 * still communicates the in-flight state.
 */
function ToastActionSpinner({ reducedMotion }: { reducedMotion: boolean }) {
  return (
    <svg
      aria-hidden="true"
      width="12"
      height="12"
      viewBox="0 0 24 24"
      fill="none"
      className={reducedMotion ? '' : 'animate-spin'}
    >
      <circle cx="12" cy="12" r="9" stroke="currentColor" strokeOpacity="0.25" strokeWidth="3" />
      <path d="M21 12a9 9 0 0 0-9-9" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
    </svg>
  );
}
