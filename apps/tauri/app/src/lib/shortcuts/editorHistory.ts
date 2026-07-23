import type { HistoryShortcutAction } from '../historyShortcuts.logic';

type HistoryShortcutHandler = (action: HistoryShortcutAction) => boolean;

interface HistoryShortcutEntry {
  handler: HistoryShortcutHandler;
  root: HTMLElement;
}

const historyShortcutEntries: HistoryShortcutEntry[] = [];

function isNodeTarget(target: EventTarget | null): target is Node {
  return typeof Node !== 'undefined' && target instanceof Node;
}

function findHistoryShortcutEntry(target: EventTarget | null): HistoryShortcutEntry | null {
  if (!isNodeTarget(target)) return null;
  for (let i = historyShortcutEntries.length - 1; i >= 0; i -= 1) {
    const entry = historyShortcutEntries[i];
    if (entry && entry.root.contains(target)) {
      return entry;
    }
  }
  return null;
}

export function registerEditorHistoryShortcutHandler(
  root: HTMLElement,
  handler: HistoryShortcutHandler,
): () => void {
  const entry: HistoryShortcutEntry = { root, handler };
  historyShortcutEntries.push(entry);
  return () => {
    const index = historyShortcutEntries.indexOf(entry);
    if (index >= 0) {
      historyShortcutEntries.splice(index, 1);
    }
  };
}

export function isEditorHistoryShortcutTarget(target: EventTarget | null): boolean {
  return findHistoryShortcutEntry(target) !== null;
}

export function dispatchEditorHistoryShortcut(
  action: HistoryShortcutAction,
  target: EventTarget | null,
): boolean {
  return findHistoryShortcutEntry(target)?.handler(action) ?? false;
}
