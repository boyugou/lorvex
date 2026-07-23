/**
 * Imperative confirm dialog — call confirm() from any code, no hooks needed.
 * ConfirmHost component subscribes to pending confirmations and renders the dialog.
 */
import type { ReactNode } from 'react';
import { useEffect, useState } from 'react';
import { dismissConfirm, enqueueConfirm, type ConfirmQueueState } from './confirm.logic';
import { readActiveConfirmTriggerElement } from './confirm.runtime';

interface ConfirmOptions {
  title: string;
  message: ReactNode;
  confirmLabel?: string;
  cancelLabel?: string;
  variant?: 'danger' | 'default';
  /**
   * explicit trigger element captured synchronously by
   * the caller. When the confirm() invocation is preceded by code that
   * synchronously closes a context menu or popover (which re-focuses
   * its launcher in the same microtask), the at-mount focus snapshot
   * inside ModalShell often catches `<body>` and the user is stranded
   * after dismiss. Passing the launcher button explicitly here threads
   * the right reference through to ModalShell.
   *
   * Falls back to `document.activeElement` (via
   * `readActiveConfirmTriggerElement`) when omitted, preserving the
   * behavior for callers that don't need the override.
   */
  triggerElement?: HTMLElement | null;
  /**
   * opt-in flag to focus the primary (Confirm) button
   * on open. Default behavior moved to Cancel-focus regardless of
   * variant — , non-`danger` confirms focused Confirm and a
   * stray Enter keypress (queued mid-typing in another field, mashed
   * to dismiss a previous toast, etc.) silently completed the action.
   * "Default Cancel-focus" treats the dialog as a checkpoint: the user
   * has to read the prompt and explicitly press Tab+Enter or click to
   * proceed. Set `focusPrimary: true` only for genuinely benign
   * one-tap confirms (e.g. "Saved. OK") where the speed of the action
   * outweighs the risk of an accidental yes.
   */
  focusPrimary?: boolean;
}

export interface PendingConfirm extends ConfirmOptions {
  id: number;
  resolve: (confirmed: boolean) => void;
  /**
   * captured synchronously at \`confirm()\` call time so
   * ModalShell can restore focus to the real trigger even when a
   * context menu or another overlay had just re-focused its launcher
   * button one microtask before. Without this, ModalShell's at-mount
   * focus snapshot sometimes caught \`<body>\` and the user was stranded
   * after dismiss.
   */
  triggerElement: HTMLElement | null;
}

type Listener = (pending: PendingConfirm | null) => void;

let nextId = 0;
let state: ConfirmQueueState<PendingConfirm> = { current: null, queue: [] };
const listeners = new Set<Listener>();

function notify() {
  for (const listener of listeners) {
    listener(state.current);
  }
}

export function confirm(options: ConfirmOptions): Promise<boolean> {
  // capture the focused element BEFORE any
  // render so ModalShell has the real trigger even if its at-mount
  // snapshot would catch `<body>` (e.g. an overlay just closed and
  // re-focused its launcher in the same microtask). When the caller
  // supplies `triggerElement` explicitly that wins — they have a
  // better reference than whatever `document.activeElement` reports.
  const explicitTrigger = options.triggerElement ?? null;
  return new Promise((resolve) => {
    state = enqueueConfirm(state, {
      ...options,
      id: ++nextId,
      resolve,
      triggerElement: explicitTrigger ?? readActiveConfirmTriggerElement(),
    });
    notify();
  });
}

function dismiss(confirmed: boolean) {
  if (!state.current) return;

  state.current.resolve(confirmed);
  state = dismissConfirm(state);
  notify();
}

export function confirmResolve() {
  dismiss(true);
}

export function confirmReject() {
  dismiss(false);
}

export function usePendingConfirm(): PendingConfirm | null {
  const [pending, setPending] = useState<PendingConfirm | null>(state.current);

  useEffect(() => {
    listeners.add(setPending);
    return () => { listeners.delete(setPending); };
  }, []);

  return pending;
}
