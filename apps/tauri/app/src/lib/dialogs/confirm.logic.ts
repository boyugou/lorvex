export interface ConfirmQueueEntry<TTrigger = HTMLElement | null> {
  id: number;
  triggerElement: TTrigger;
  resolve: (confirmed: boolean) => void;
}

export interface ConfirmQueueState<TEntry extends ConfirmQueueEntry = ConfirmQueueEntry> {
  current: TEntry | null;
  queue: TEntry[];
}

export function enqueueConfirm<TEntry extends ConfirmQueueEntry>(
  state: ConfirmQueueState<TEntry>,
  entry: TEntry,
): ConfirmQueueState<TEntry> {
  if (!state.current) {
    return { current: entry, queue: state.queue };
  }

  return {
    current: state.current,
    queue: [...state.queue, entry],
  };
}

export function dismissConfirm<TEntry extends ConfirmQueueEntry>(
  state: ConfirmQueueState<TEntry>,
): ConfirmQueueState<TEntry> {
  const [next, ...rest] = state.queue;
  return {
    current: next ?? null,
    queue: rest,
  };
}
