import { useCallback, useMemo, useState } from 'react';
import { useQueryClient, type QueryClient } from '@tanstack/react-query';

import { confirm } from '@/lib/dialogs/confirm';
import { deleteList } from '@/lib/ipc/tasks/lists';
import { reportClientError } from '@/lib/errors/errorLogging';
import { toast } from '@/lib/notifications/toast';
import { useSnapshotUndoToast } from '@/lib/hooks/useSnapshotUndoToast';
import {
  QUERY_KEYS,
  invalidateTaskCollectionQueries,
  invalidateTodaySurfaceQueries,
} from '@/lib/query/queryKeys';
import { evictDeletedListFromCache } from '../list-view/deleteCache';
import type { TranslationKey } from '@/lib/i18n';
import type { ContextMenuItem, ContextMenuPosition } from '../context-menu/ContextMenu';
import type { View } from '@/lib/types';

interface ListContextMenuState {
  listId: string;
  listName: string;
  position: ContextMenuPosition;
  /**
   * launcher element captured synchronously from the
   * contextmenu event so we can hand it to confirm() for accurate
   * focus restore. Without this, the menu's "Delete" item closes the
   * menu (re-focusing the row button) and immediately opens the
   * confirm modal — but `document.activeElement` at confirm() call
   * time can race to `<body>` depending on platform menu dismissal
   * timing, leaving focus stranded after the modal closes.
   */
  triggerElement: HTMLElement | null;
}

interface UseListContextMenuReturn {
  contextMenu: ListContextMenuState | null;
  contextMenuItems: ContextMenuItem[];
  handleContextMenu: (e: React.MouseEvent, listId: string, listName: string) => void;
  /**
   * Open the context menu from a non-mouse event (Shift+F10, the macOS
   * `.` shortcut, etc.). Anchors the menu at the trigger element's
   * bounding rect so it visually attaches to the item the user has
   * focused, and forwards the trigger so confirm() can restore focus
   * after a destructive action — same contract as `handleContextMenu`.
   */
  openContextMenuForElement: (
    trigger: HTMLElement,
    listId: string,
    listName: string,
  ) => void;
  closeContextMenu: () => void;
}

/**
 * Cache invalidations to run after a list-delete or list-restore.
 * Extracted so the success path (post-delete) and the undo path
 * (post-restore) share the exact same invalidation set — anything that
 * counts/displays lists or list-scoped tasks needs to refetch.
 */
function invalidateListSurfaces(qc: QueryClient): void {
  void qc.invalidateQueries({ queryKey: QUERY_KEYS.lists() });
  invalidateTodaySurfaceQueries(qc);
  invalidateTaskCollectionQueries(qc);
}

export function useListContextMenu(
  onNavigate: (view: View) => void,
  t: (key: TranslationKey) => string,
): UseListContextMenuReturn {
  const [contextMenu, setContextMenu] = useState<ListContextMenuState | null>(null);
  const qc = useQueryClient();
  const showSnapshotUndoToast = useSnapshotUndoToast();

  const handleContextMenu = useCallback((e: React.MouseEvent, listId: string, listName: string) => {
    e.preventDefault();
    const triggerElement = e.currentTarget instanceof HTMLElement ? e.currentTarget : null;
    setContextMenu({ listId, listName, position: { x: e.clientX, y: e.clientY }, triggerElement });
  }, []);

  const openContextMenuForElement = useCallback(
    (trigger: HTMLElement, listId: string, listName: string) => {
      const rect = trigger.getBoundingClientRect();
      // Anchor at the bottom-center of the focused row so the menu visually
      // attaches to the item the user navigated to. Centering on width
      // keeps the menu from sliding off the leading edge in narrow
      // sidebars; using `bottom` mirrors where a right-click at the row
      // baseline would have placed it.
      const x = Math.round(rect.left + rect.width / 2);
      const y = Math.round(rect.bottom);
      setContextMenu({ listId, listName, position: { x, y }, triggerElement: trigger });
    },
    [],
  );

  const closeContextMenu = useCallback(() => {
    setContextMenu(null);
  }, []);

  const contextMenuItems: ContextMenuItem[] = useMemo(() => {
    if (!contextMenu) return [];
    return [
      {
        key: 'rename',
        label: t('sidebar.renameList'),
        onSelect: () => {
          setContextMenu(null);
          onNavigate({ type: 'list', listId: contextMenu.listId, rename: true });
        },
      },
      { key: 'sep', label: '', separator: true },
      {
        key: 'delete',
        label: t('sidebar.deleteList'),
        danger: true,
        onSelect: () => {
          // capture the launcher reference BEFORE we
          // tear down the menu (which clears `contextMenu` in the next
          // commit). Then forward it as `triggerElement` so the
          // confirm dialog restores focus to the originating list row,
          // not to `<body>`.
          const trigger = contextMenu.triggerElement;
          setContextMenu(null);
          void confirm({
            title: t('sidebar.deleteList'),
            message: t('list.deleteConfirm'),
            variant: 'danger',
            confirmLabel: t('sidebar.deleteList'),
            triggerElement: trigger,
          }).then(async (confirmed) => {
            if (!confirmed) return;
            const targetListId = contextMenu.listId;
            try {
              // Cancel any in-flight per-list query so the delete
              // doesn't race against a refetch that would re-seed the
              // cache with the about-to-disappear row. Mirrors the
              // canonical handler in
              // `useListViewController.handleDeleteList`.
              await qc.cancelQueries({ queryKey: QUERY_KEYS.list(targetListId) });
              const result = await deleteList(targetListId);
              // Drop the deleted list from the lists cache + remove
              // its per-list cache entry, then invalidate every
              // surface that displays lists or list-scoped tasks.
              // Without this, the sidebar context-menu delete left
              // the row visible until natural staleness fired a
              // refetch.
              evictDeletedListFromCache(qc, result.deleted_list_id);
              invalidateTodaySurfaceQueries(qc);
              invalidateTaskCollectionQueries(qc);
              // snapshot-based undo for list delete.
              // Defer the "navigate to Today" step until the undo
              // window passes — clicking Undo within ~5s otherwise
              // strands the user on Today even though the list they
              // restored is now visible in the sidebar again. Lists
              // hold no edges (delete is gated behind the "no
              // assigned tasks" invariant), so the restore is a
              // single INSERT OR REPLACE on the lists table.
              showSnapshotUndoToast({
                kind: 'list',
                token: result.undo_token,
                successKey: 'list.deleteSuccess',
                restoredKey: 'list.restored',
                invalidate: invalidateListSurfaces,
                onAfterUndoExpired: () => onNavigate({ type: 'today' }),
              });
            } catch (err) {
              reportClientError('sidebar', 'deleteList failed', err);
              toast.errorWithDetail(err, t('common.error'));
            }
          });
        },
      },
    ];
  }, [contextMenu, onNavigate, qc, showSnapshotUndoToast, t]);

  return {
    contextMenu,
    contextMenuItems,
    handleContextMenu,
    openContextMenuForElement,
    closeContextMenu,
  };
}
