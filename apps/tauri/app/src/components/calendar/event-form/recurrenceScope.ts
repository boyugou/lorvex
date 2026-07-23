/**
 * Imperative recurrence-scope picker — call `pickRecurrenceScope()` from any
 * code path that needs to ask the user how a destructive/edit action on a
 * recurring calendar event should propagate. Mirrors the `confirm()` API
 * shape (see `app/src/lib/confirm.ts`) but resolves to a 3-way choice
 * (`'thisOnly' | 'thisAndFollowing' | 'allInSeries'`) or `null` when the
 * user dismisses.
 *
 * Mounted once via `<RecurrenceScopeHost />` at the app root, alongside
 * `<ConfirmHost />`. We intentionally do not piggyback on the
 * binary `confirm()` — promoting one of the buttons to "primary" would
 * push users toward the wrong answer when all three propagation scopes
 * are valid.
 */
import { useEffect, useState } from 'react';

export type RecurrenceScope = 'thisOnly' | 'thisAndFollowing' | 'allInSeries';

/**
 * Typed cancellation error rejected by `pickRecurrenceScope()` when the
 * host (`<RecurrenceScopeHost />`) unmounts mid-prompt — e.g. the user
 * navigated away while the radio dialog was still open. Callers should
 * catch this specifically and treat it as a clean user cancellation
 * (no retry, no error toast).
 */
export class RecurrenceScopeCancelled extends Error {
  constructor() {
    super('RecurrenceScopeCancelled');
    this.name = 'RecurrenceScopeCancelled';
  }
}

type RecurrenceScopeMode = 'edit' | 'delete';

interface PickRecurrenceScopeOptions {
  mode: RecurrenceScopeMode;
  /** Optional explicit trigger element for focus restoration. */
  triggerElement?: HTMLElement | null;
}

export interface PendingRecurrenceScope extends PickRecurrenceScopeOptions {
  id: number;
  resolve: (scope: RecurrenceScope | null) => void;
  reject: (error: RecurrenceScopeCancelled) => void;
  triggerElement: HTMLElement | null;
}

type Listener = (pending: PendingRecurrenceScope | null) => void;

let nextId = 0;
let current: PendingRecurrenceScope | null = null;
const queue: PendingRecurrenceScope[] = [];
const listeners = new Set<Listener>();

function notify() {
  for (const listener of listeners) listener(current);
}

function readActiveTrigger(): HTMLElement | null {
  if (typeof document === 'undefined') return null;
  const active = document.activeElement;
  return active instanceof HTMLElement ? active : null;
}

export function pickRecurrenceScope(
  options: PickRecurrenceScopeOptions,
): Promise<RecurrenceScope | null> {
  return new Promise((resolve, reject) => {
    const pending: PendingRecurrenceScope = {
      ...options,
      id: ++nextId,
      resolve,
      reject,
      triggerElement: options.triggerElement ?? readActiveTrigger(),
    };
    if (current) {
      queue.push(pending);
    } else {
      current = pending;
      notify();
    }
  });
}

/**
 * Reject any in-flight + queued prompts with `RecurrenceScopeCancelled`.
 * Called by `<RecurrenceScopeHost />` on unmount so `await
 * pickRecurrenceScope()` callers don't deadlock when the host disappears.
 */
export function recurrenceScopeAbortAll(): void {
  const cancelled = new RecurrenceScopeCancelled();
  if (current) {
    current.reject(cancelled);
    current = null;
  }
  while (queue.length > 0) {
    const pending = queue.shift();
    pending?.reject(cancelled);
  }
  notify();
}

function dismiss(scope: RecurrenceScope | null) {
  if (!current) return;
  current.resolve(scope);
  current = queue.shift() ?? null;
  notify();
}

export function recurrenceScopeResolve(scope: RecurrenceScope) {
  dismiss(scope);
}

export function recurrenceScopeReject() {
  dismiss(null);
}

export function usePendingRecurrenceScope(): PendingRecurrenceScope | null {
  const [pending, setPending] = useState<PendingRecurrenceScope | null>(current);
  useEffect(() => {
    listeners.add(setPending);
    return () => { listeners.delete(setPending); };
  }, []);
  return pending;
}
