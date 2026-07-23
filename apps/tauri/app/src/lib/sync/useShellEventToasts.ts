/**
 * App-shell-level subscriber for backend event channels that surface
 * non-blocking notifications:
 *
 *   - `lorvex://sync-notice` — informational toast keyed by an i18n
 *     string passed from the Rust side. The current emitter (`pull.rs`)
 *     uses this to surface the "long-offline resync recovered" notice;
 *     the listener resolves the key against the active locale.
 *
 *   - `lorvex://data-reset-failed` — fired when the Settings → Data →
 *     "Delete all data" command rolls back or partially completes. The
 *     IPC caller already sees the typed error, but the sibling event
 *     guarantees the user gets a toast even when the result has been
 *     consumed before render.
 *
 *   - `lorvex://notification-action-error` — fired when a notification
 *     center action (Complete, Snooze, …) fails to apply. The durable
 *     `error_logs` row is best-effort; this listener guarantees the
 *     user sees the failure even when the DB write succeeded
 *     transparently.
 *
 * All channels are mounted ONCE at the main-window scope. Overlay windows
 * (popover, focus) deliberately do not subscribe — duplicate toasts across
 * windows would stack on top of each other for the same backend signal.
 */
import { useEffect, useRef } from 'react';
import { listen } from '@tauri-apps/api/event';

import { reportClientError } from '../errors/errorLogging';
import { useI18n } from '../i18n';
import { createAsyncTauriListenerScope } from '../tauriListenerLifecycle';
import { toast } from '../notifications/toast';
import type { TranslationKey } from '@/locales';
import {
  DATA_RESET_FAILED_EVENT,
  NOTIFICATION_ACTION_ERROR_EVENT,
  SYNC_NOTICE_EVENT,
} from './shellEventChannels';

interface SyncNoticePayload {
  /** Backend-emitted key; must match an entry in `app/src/locales/*.ts`. */
  i18n_key?: unknown;
}

interface DataResetFailedPayload {
  reason?: unknown;
  rolled_back?: unknown;
}

interface NotificationActionErrorPayload {
  action?: unknown;
  taskId?: unknown;
  message?: unknown;
}

/**
 * Drop a string field through a string-only filter so a malformed
 * backend payload (e.g. number, null, trimmed-to-empty) does not
 * propagate `undefined` into `toast.info(t(...))` and surface as
 * "undefined" to the user.
 */
function readNonEmptyString(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

export function useShellEventToasts(): void {
  const { t } = useI18n();

  // Stash render-time dependencies in refs so the listener effect
  // below stays bound to the component mount. Re-subscribing on a
  // callback or locale change would tear down all four channels; a
  // backend event fired before the new listener promise resolves would
  // land at neither listener (old one gated by `cancelled`, new one
  // not yet installed).
  const translateRef = useRef(t);

  useEffect(() => {
    translateRef.current = t;
  }, [t]);

  useEffect(() => {
    let cancelled = false;
    const listeners = createAsyncTauriListenerScope();

    const subscribe = <Payload>(
      event: string,
      handler: (payload: Payload) => void,
      label: string,
    ) => {
      listeners.add(
        listen<Payload>(event, (e) => {
          if (cancelled) return;
          try {
            handler(e.payload);
          } catch (error) {
            // Defensive: a broken handler must never tear down the rest
            // of the listener bundle. The closure may rethrow if a future
            // payload shape changes; log and move on.
            reportClientError(
              `shellEvents.${label}.handler`,
              `Shell event handler threw on ${event}`,
              error,
              undefined,
              'warn',
            );
          }
        }),
        (error) => {
          reportClientError(
            `shellEvents.${label}.subscribe`,
            `Failed to subscribe to ${event}`,
            error,
          );
        },
      );
    };

    subscribe<SyncNoticePayload>(SYNC_NOTICE_EVENT, (payload) => {
      const key = readNonEmptyString(payload?.i18n_key);
      if (!key) {
        reportClientError(
          'shellEvents.syncNotice.malformed',
          'Dropped sync-notice event with missing i18n_key',
          new Error(JSON.stringify(payload).slice(0, 200)),
          undefined,
          'warn',
        );
        return;
      }
      // The backend ships an arbitrary key string; the cast routes it
      // through the localized lookup. An unknown key falls back to the
      // key text itself (see `translate` in `app/src/lib/i18n.tsx`),
      // which is still readable diagnostic output rather than a crash.
      toast.info(translateRef.current(key as TranslationKey));
    }, 'syncNotice');

    subscribe<DataResetFailedPayload>(DATA_RESET_FAILED_EVENT, (payload) => {
      const reason = readNonEmptyString(payload?.reason);
      // Surface the backend reason verbatim (it is already a
      // human-readable summary on the Rust side); fall back to the
      // localized headline when it is missing. `errorWithDetail`
      // accepts an `unknown` and runs the same sanitizer as the IPC
      // error path, so a plain string is the right input here.
      toast.errorWithDetail(reason, translateRef.current('shellEvents.dataResetFailed'));
    }, 'dataResetFailed');

    subscribe<NotificationActionErrorPayload>(NOTIFICATION_ACTION_ERROR_EVENT, (payload) => {
      const message = readNonEmptyString(payload?.message);
      toast.errorWithDetail(message, translateRef.current('shellEvents.notificationActionFailed'));
    }, 'notificationActionError');

    return () => {
      cancelled = true;
      listeners.dispose();
    };
  }, []);
}
