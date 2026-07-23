import { useCallback, useEffect, useRef, useState } from 'react';
import { useI18n } from '@/lib/i18n';
import { confirmReject, confirmResolve, usePendingConfirm, type PendingConfirm } from '@/lib/dialogs/confirm';
import { Modal } from './Modal';

/**
 * Global confirm dialog host. Mount once in the app root.
 * Renders when a pending confirm() call exists.
 */
export function ConfirmHost() {
  const pending = usePendingConfirm();

  if (!pending) return null;

  // keying the inner component by `pending.id` resets
  // the local "settling" state when a fresh confirm() call queues up
  // behind a previous one. Without the key, the second prompt would
  // mount with `settling=true` left over from the first.
  return <ConfirmDialogInner key={pending.id} pending={pending} />;
}

function ConfirmDialogInner({ pending }: { pending: PendingConfirm }) {
  const { t } = useI18n();
  const cancelRef = useRef<HTMLButtonElement>(null);
  const confirmRef = useRef<HTMLButtonElement>(null);

  /**
   * confirm() resolves the promise synchronously and
   * the dialog unmounts on the next React commit. A determined user
   * (or a stray double-click on a trackpad) can fire `onClick` twice
   * before the unmount lands, which calls `confirmResolve()` again,
   * fires the next queued confirm with the previous click, and feels
   * like the destructive action ran twice. We track `settling` in
   * local state and ref so the second click no-ops in both the
   * synchronous handler and the rendered button (which dims to a
   * disabled state to communicate that the action is in flight).
   */
  const [settling, setSettling] = useState(false);
  const settlingRef = useRef(false);

  const handleResolve = useCallback(() => {
    if (settlingRef.current) return;
    settlingRef.current = true;
    setSettling(true);
    confirmResolve();
  }, []);
  const handleReject = useCallback(() => {
    if (settlingRef.current) return;
    settlingRef.current = true;
    setSettling(true);
    confirmReject();
  }, []);

  useEffect(() => {
    // Cancel-focus is the safe default for ALL
    // confirms (not just `variant === 'danger'`). A stray Enter — queued
    // mid-typing in another field, mashed to dismiss a stale toast,
    // bounced off a context menu — should never silently commit an
    // action just because the dialog happens to be non-destructive.
    // Callers that genuinely want primary-focus (a benign "Saved. OK")
    // must opt in via `focusPrimary: true`.
    if (pending.focusPrimary) {
      confirmRef.current?.focus();
    } else {
      cancelRef.current?.focus();
    }
  }, [pending.focusPrimary]);

  const confirmBtnClass = pending.variant === 'danger'
    ? 'chip-danger chip-danger-interactive'
    : 'bg-accent/15 hover:bg-accent/25 text-accent';

  return (
    <Modal
      open
      onClose={handleReject}
      size="sm"
      panelClassName="px-6 py-5 mx-4"
      ariaLabelledBy="confirm-dialog-title"
      ariaDescribedBy="confirm-dialog-message"
      triggerElement={pending.triggerElement}
    >
      <h3 id="confirm-dialog-title" className="text-text-primary text-sm font-semibold mb-2">
        {pending.title}
      </h3>
      <p
        className="text-text-secondary text-sm leading-relaxed mb-6"
        // Mark the prompt as the dialog's accessible description so SR
        // users hear it after the title without our needing a separate
        // aria-describedby plumbing through Modal.
        id="confirm-dialog-message"
      >
        {pending.message}
      </p>
      <div className="flex gap-2.5 justify-end">
        <button
          ref={cancelRef}
          type="button"
          onClick={handleReject}
          disabled={settling}
          className="rounded-r-control border border-card bg-surface-2/50 text-text-secondary text-xs font-medium px-4 py-2 hover:bg-surface-3/60 active:scale-[0.97] transition-[color,background-color,transform] focus-ring-strong disabled:cursor-not-allowed disabled:opacity-50 disabled:active:scale-100"
        >
          {pending.cancelLabel ?? t('common.cancel')}
        </button>
        <button
          ref={confirmRef}
          type="button"
          onClick={handleResolve}
          disabled={settling}
          aria-busy={settling || undefined}
          className={`rounded-r-control text-xs font-semibold px-4 py-2 active:scale-[0.97] transition-[color,background-color,transform] focus-ring-strong disabled:cursor-not-allowed disabled:opacity-60 disabled:active:scale-100 ${confirmBtnClass}`}
        >
          {pending.confirmLabel ?? t('common.confirm')}
        </button>
      </div>
    </Modal>
  );
}
