import * as React from 'react';

import type { AnnouncementEntry } from '@/lib/announce';
import { subscribeAnnouncer } from '@/lib/announce';
import {
  createBrowserAnnouncerTimerHost,
  dequeueAnnouncementEntry,
  enqueueAnnouncementEntry,
  scheduleAnnouncementDequeue,
} from './Announcer.runtime';

type AnnouncementLiveRegionProps = {
  entry: AnnouncementEntry | null;
  role: 'status' | 'alert';
  priority: 'polite' | 'assertive';
};

const announcerTimerHost = createBrowserAnnouncerTimerHost();

export function AnnouncementLiveRegion({
  entry,
  role,
  priority,
}: AnnouncementLiveRegionProps) {
  return (
    <div
      role={role}
      aria-live={priority}
      aria-atomic="true"
      className="sr-only"
    >
      {entry ? <span>{entry.message}</span> : null}
      {entry ? <span aria-hidden="true" data-announcement-seq={entry.id} /> : null}
    </div>
  );
}

/**
 * dual visually-hidden live regions that callers push
 * status messages through via the module-level `announce()` API.
 *
 * The dual region matches `ToastContainer` — assertive for errors
 * that should preempt polite speech (e.g. a sync failure), polite
 * for success / progress announcements.
 *
 * Messages are cleared after 800 ms so the same message can be
 * re-announced without needing a distinct string (SR don't
 * re-announce identical aria-live content).
 */
/**
 * Re-arm the dequeue timer when the head entry's identity changes
 * (its `.id`). The entry object itself is recreated on every queue
 * mutation but represents the same announcement, so the exhaustive-deps
 * lint would otherwise force `polite` / `assertive` into the dep array
 * and dequeue eagerly on every queue churn.
 */
function useAnnouncementDequeueTimer(
  entry: AnnouncementEntry | null,
  setQueue: React.Dispatch<React.SetStateAction<AnnouncementEntry[]>>,
) {
  React.useEffect(() => {
    if (!entry) return;
    return scheduleAnnouncementDequeue(
      announcerTimerHost,
      () => setQueue((queue) => dequeueAnnouncementEntry(queue)),
    );
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [entry?.id]);
}

export default function Announcer() {
  const [politeQueue, setPoliteQueue] = React.useState<AnnouncementEntry[]>([]);
  const [assertiveQueue, setAssertiveQueue] = React.useState<AnnouncementEntry[]>([]);
  const polite = politeQueue[0] ?? null;
  const assertive = assertiveQueue[0] ?? null;

  React.useEffect(() => {
    return subscribeAnnouncer((entry) => {
      if (entry.priority === 'assertive') {
        setAssertiveQueue((queue) => enqueueAnnouncementEntry(queue, entry));
      } else {
        setPoliteQueue((queue) => enqueueAnnouncementEntry(queue, entry));
      }
    });
  }, []);

  useAnnouncementDequeueTimer(polite, setPoliteQueue);
  useAnnouncementDequeueTimer(assertive, setAssertiveQueue);

  return (
    <>
      <AnnouncementLiveRegion entry={polite} role="status" priority="polite" />
      <AnnouncementLiveRegion entry={assertive} role="alert" priority="assertive" />
    </>
  );
}
