/**
 * Public `toast` API — the four-channel surface every caller uses to
 * emit a toast. Each method normalizes its overload shape (string-context
 * vs action-object) and computes the final auto-dismiss duration before
 * delegating to the store's `show`.
 *
 * Length-scaling rationale lives in `durations.ts`; this file is a thin
 * caller-facing adapter and intentionally carries no module state.
 */

import { toUserFacingErrorMessage } from '../../ipc/core';
import {
  ACTIONABLE_INFO_TOAST_DURATION_MS,
  ACTIONABLE_SUCCESS_TOAST_DURATION_MS,
  ERROR_TOAST_DURATION_MS,
  INFO_TOAST_DURATION_MS,
  MAX_NON_SUCCESS_ACTIONABLE_DURATION_MS,
  MAX_SUCCESS_ACTIONABLE_DURATION_MS,
  SUCCESS_TOAST_DURATION_MS,
  WARNING_TOAST_DURATION_MS,
  scaleActionableDuration,
} from './durations';
import { show } from './store';
import type { ToastAction, ToastActionableOptions } from './types';

export const toast = {
  /** Show a success toast.
   *  @param actionOrContext  Either an action (for an actionable toast) or a
   *                          string context for dedup.
   *  @param context          Dedup discriminator when an action is passed.
   *  @param options          Fine-grained overrides for actionable toasts:
   *                          custom duration (e.g. bulk operations whose
   *                          visibility should scale with count) and/or
   *                          `priority: true` to protect against eviction. */
  success: (
    message: string,
    actionOrContext?: ToastAction | string,
    context?: string,
    options?: ToastActionableOptions,
  ) => {
    if (typeof actionOrContext === 'string') {
      // Called as toast.success(message, context)
      show(message, 'success', SUCCESS_TOAST_DURATION_MS, undefined, actionOrContext);
    } else {
      // Called as toast.success(message) or toast.success(message, action, context?, options?)
      // long actionable messages get a length-scaled
      // duration (capped < 5s undo hold) so users have time to read
      // before the Undo button vanishes.
      const duration =
        options?.durationMs ??
        (actionOrContext
          ? scaleActionableDuration(
              ACTIONABLE_SUCCESS_TOAST_DURATION_MS,
              message,
              MAX_SUCCESS_ACTIONABLE_DURATION_MS,
            )
          : SUCCESS_TOAST_DURATION_MS);
      show(message, 'success', duration, actionOrContext, context, options?.priority);
    }
  },
  /** Show an error toast.
   *  Accepts an optional `action` (e.g. Retry / Open System Settings) so
   *  the user can take the remediation step directly from the toast
   *  instead of hunting through Settings. When `options.priority` is
   *  set, the toast survives MAX_TOASTS eviction — used for
   *  high-consequence errors such as the actionable sync-error toasts. */
  error: (
    message: string,
    actionOrOptions?: ToastAction,
    options?: ToastActionableOptions,
  ) => {
    const action = actionOrOptions;
    // scale the dwell time for long actionable error
    // messages so the Retry / Open-Settings affordance stays readable.
    const duration =
      options?.durationMs ??
      (action
        ? scaleActionableDuration(
            ERROR_TOAST_DURATION_MS,
            message,
            MAX_NON_SUCCESS_ACTIONABLE_DURATION_MS,
          )
        : ERROR_TOAST_DURATION_MS);
    show(message, 'error', duration, action, options?.context, options?.priority);
  },
  /** Show a warning toast.
   *  warning sits between info and error. Use it for partial-success
   *  outcomes where the primary operation worked but a follow-up step
   *  failed in a way the user must address (e.g. an orphan row that needs
   *  manual cleanup). `error` was a poor fit — it implied total failure
   *  and contradicted the success copy users had just seen. Mirrors the
   *  `error` shape (optional action + options). */
  warning: (
    message: string,
    actionOrOptions?: ToastAction,
    options?: ToastActionableOptions,
  ) => {
    const action = actionOrOptions;
    const duration =
      options?.durationMs ??
      (action
        ? scaleActionableDuration(
            WARNING_TOAST_DURATION_MS,
            message,
            MAX_NON_SUCCESS_ACTIONABLE_DURATION_MS,
          )
        : WARNING_TOAST_DURATION_MS);
    show(message, 'warning', duration, action, options?.context, options?.priority);
  },
  /** Show an error toast that surfaces backend error details when available.
   *  Falls back to `fallback` for opaque or empty errors. */
  errorWithDetail: (error: unknown, fallback: string) =>
    show(toUserFacingErrorMessage(error, fallback), 'error', ERROR_TOAST_DURATION_MS),
  /** Show an info toast.
   *  @param context  Optional discriminator for dedup (e.g. entity ID). */
  info: (
    message: string,
    actionOrContext?: ToastAction | string,
    context?: string,
    options?: ToastActionableOptions,
  ) => {
    if (typeof actionOrContext === 'string') {
      show(message, 'info', INFO_TOAST_DURATION_MS, undefined, actionOrContext);
    } else {
      // same length-scaling treatment as actionable
      // success/error so long info copy with an action stays visible.
      const duration =
        options?.durationMs ??
        (actionOrContext
          ? scaleActionableDuration(
              ACTIONABLE_INFO_TOAST_DURATION_MS,
              message,
              MAX_NON_SUCCESS_ACTIONABLE_DURATION_MS,
            )
          : INFO_TOAST_DURATION_MS);
      show(message, 'info', duration, actionOrContext, context, options?.priority);
    }
  },
};
