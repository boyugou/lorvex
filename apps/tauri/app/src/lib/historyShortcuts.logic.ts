export type HistoryShortcutAction = 'undo' | 'redo';

export interface HistoryShortcutEventLike {
  altKey: boolean;
  ctrlKey: boolean;
  key: string;
  metaKey: boolean;
  shiftKey: boolean;
}

type HistoryShortcutRoute = 'editor' | 'native' | 'toast' | 'none';

export function getHistoryShortcutAction(
  event: HistoryShortcutEventLike,
): HistoryShortcutAction | null {
  if (!(event.metaKey || event.ctrlKey) || event.altKey) return null;

  const key = event.key.toLowerCase();
  if (key === 'z') {
    return event.shiftKey ? 'redo' : 'undo';
  }
  if (key === 'y' && !event.shiftKey) {
    return 'redo';
  }
  return null;
}

interface ResolveHistoryShortcutRouteArgs {
  action: HistoryShortcutAction;
  editorOwnsTarget: boolean;
  targetIgnoresShortcut: boolean;
  activeElementIgnoresShortcut: boolean;
}

export function resolveHistoryShortcutRoute({
  action,
  activeElementIgnoresShortcut,
  editorOwnsTarget,
  targetIgnoresShortcut,
}: ResolveHistoryShortcutRouteArgs): HistoryShortcutRoute {
  if (editorOwnsTarget) return 'editor';
  if (targetIgnoresShortcut || activeElementIgnoresShortcut) return 'native';
  if (action === 'undo') return 'toast';
  return 'none';
}

export function resolveUnhandledEditorHistoryShortcutRoute(
  action: HistoryShortcutAction,
): Exclude<HistoryShortcutRoute, 'editor' | 'native'> {
  return action === 'undo' ? 'toast' : 'none';
}
