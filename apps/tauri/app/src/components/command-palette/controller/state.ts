import { useMemo, useState } from 'react';
import { keepPreviousData, useQuery } from '@tanstack/react-query';

import { useLazyRef } from '@/lib/useLazyRef';
import { getAllLists } from '@/lib/ipc/tasks/lists';
import type { Task } from '@/lib/ipc/tasks/models';
import { searchTasks } from '@/lib/ipc/tasks/queries';
import type { TranslationKey } from '@/locales';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { STALE_DEFAULT } from '@/lib/query/timing';
import { formatShortcut } from '@/lib/shortcuts';
import { useDebounced } from '@/lib/useDebounced';
import { NAV_KEYS } from '../model';
import type { PaletteNavItem } from '../types';

interface UsePaletteStateArgs {
  t: (key: TranslationKey) => string;
}

export function usePaletteState({ t }: UsePaletteStateArgs) {
  const [query, setQuery] = useState('');
  const [selectedIdx, setSelectedIdx] = useState(0);
  const [selectedResultKey, setSelectedResultKey] = useState<string | null>(null);
  const [moveTask, setMoveTask] = useState<Task | null>(null);
  const [confirmArchiveListId, setConfirmArchiveListId] = useState<string | null>(null);
  const [isComposing, setIsComposing] = useState(false);
  // palette options are now <div role="option"> rather
  // than <button>, so the ref map's value type widens to HTMLElement.
  const optionRefs = useLazyRef(() => new Map<string, HTMLElement>());

  const isScopedListQuery = !moveTask && query.trim().startsWith('@');
  const navItems = useMemo(
    () => NAV_KEYS.map((item) => ({
      ...item,
      label: t(item.labelKey),
      shortcut: item.shortcut ? formatShortcut(item.shortcut) : undefined,
    })),
    [t],
  ) satisfies Array<Omit<PaletteNavItem, 'kind'>>;

  const { data: lists = [] } = useQuery({
    queryKey: QUERY_KEYS.lists(),
    queryFn: ({ signal }) => getAllLists(signal),
    staleTime: STALE_DEFAULT,
  });

  const debouncedQuery = useDebounced(query.trim(), 300);
  const { data: searchResults = [], isFetching: isSearching } = useQuery({
    queryKey: QUERY_KEYS.search(debouncedQuery),
    queryFn: ({ signal }) => searchTasks(debouncedQuery, false, 50, signal),
    enabled: debouncedQuery.length >= 2 && !isScopedListQuery,
    placeholderData: keepPreviousData,
  });

  return {
    confirmArchiveListId,
    isComposing,
    isScopedListQuery,
    isSearching,
    lists,
    moveTask,
    navItems,
    optionRefs,
    query,
    searchResults,
    selectedIdx,
    selectedResultKey,
    setConfirmArchiveListId,
    setIsComposing,
    setMoveTask,
    setQuery,
    setSelectedIdx,
    setSelectedResultKey,
  };
}
