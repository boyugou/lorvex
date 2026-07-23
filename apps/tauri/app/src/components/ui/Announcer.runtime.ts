import type { AnnouncementEntry } from '@/lib/announce';

type AnnouncementQueue = AnnouncementEntry[];

export interface AnnouncerTimerHost {
  clearTimeout: (handle: unknown) => void;
  setTimeout: (callback: () => void, delayMs: number) => unknown;
}

export const ANNOUNCEMENT_DEQUEUE_DELAY_MS = 800;

export function createBrowserAnnouncerTimerHost(): AnnouncerTimerHost {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

export function enqueueAnnouncementEntry(
  queue: AnnouncementQueue,
  entry: AnnouncementEntry,
): AnnouncementQueue {
  return [...queue, entry];
}

export function dequeueAnnouncementEntry(queue: AnnouncementQueue): AnnouncementQueue {
  if (queue.length <= 1) return [];
  return queue.slice(1);
}

export function scheduleAnnouncementDequeue(
  host: AnnouncerTimerHost,
  dequeue: () => void,
  delayMs = ANNOUNCEMENT_DEQUEUE_DELAY_MS,
): () => void {
  const handle = host.setTimeout(dequeue, delayMs);
  return () => host.clearTimeout(handle);
}
