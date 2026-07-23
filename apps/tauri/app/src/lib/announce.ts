/**
 * a visually-hidden live region that non-toast callers
 * can push brief status messages through. Toasts already handle
 * user-visible feedback via `ToastContainer`; this hook is for
 * actions that complete silently in the UI but need to be audible
 * for screen-reader users — sync complete, autosave success, bulk
 * keyboard move done, etc.
 *
 * Design:
 *   - One module-level Set of subscribers (the `<Announcer>` host).
 *   - Callers call `announce(message, { priority })`. The host picks
 *     up the next message and renders it inside either a
 *     `role="status"` (polite, default) or `role="alert"` (assertive)
 *     node. SR reads the new content; the node is cleared after a
 *     short grace period so subsequent identical messages still fire.
 *   - No React context; the host mounts once at the app shell and
 *     any caller anywhere can push without threading props.
 */

type Priority = 'polite' | 'assertive';

export interface AnnouncementEntry {
  id: number;
  message: string;
  priority: Priority;
}

type Listener = (entry: AnnouncementEntry) => void;

const listeners = new Set<Listener>();
let nextAnnouncementId = 1;

export function announce(message: string, options?: { priority?: Priority }): void {
  const trimmed = message.trim();
  if (!trimmed) return;
  const entry: AnnouncementEntry = {
    id: nextAnnouncementId++,
    message: trimmed,
    priority: options?.priority ?? 'polite',
  };
  for (const listener of listeners) {
    listener(entry);
  }
}

export function subscribeAnnouncer(listener: Listener): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

export function resetAnnouncerIdsForTests(): void {
  nextAnnouncementId = 1;
}
