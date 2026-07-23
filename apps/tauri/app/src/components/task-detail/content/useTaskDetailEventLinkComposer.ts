import { useCallback, useState } from 'react';
import type { UnifiedCalendarEvent } from '@/lib/ipc/calendar';

interface UseTaskDetailEventLinkComposerArgs {
  onLinkCanonicalEvent: (eventId: string) => void;
  onLinkProviderEvent: (providerKind: string, providerScope: string, providerEventKey: string) => void;
}

export function useTaskDetailEventLinkComposer({
  onLinkCanonicalEvent,
  onLinkProviderEvent,
}: UseTaskDetailEventLinkComposerArgs) {
  const [adding, setAdding] = useState(false);

  const toggleAdding = useCallback(() => {
    setAdding((current) => !current);
  }, []);

  const cancelAdding = useCallback(() => {
    setAdding(false);
  }, []);

  const handleSelectEvent = useCallback((event: UnifiedCalendarEvent) => {
    if (event.kind === 'provider') {
      const parts = event.id.split(':');
      if (parts.length < 3) {
        return;
      }
      const providerKind = parts[0]!;
      const providerScope = parts[1]!;
      const providerEventKey = parts.slice(2).join(':');
      onLinkProviderEvent(providerKind, providerScope, providerEventKey);
      setAdding(false);
      return;
    }

    onLinkCanonicalEvent(event.id);
    setAdding(false);
  }, [onLinkCanonicalEvent, onLinkProviderEvent]);

  return {
    adding,
    cancelAdding,
    handleSelectEvent,
    toggleAdding,
  };
}
