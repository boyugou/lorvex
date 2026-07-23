import { useCallback, useState } from 'react';

import type { ContextMenuPosition } from '../context-menu/ContextMenu';
import type { HabitWithStats } from '@/lib/ipc/habits';

export interface HabitCardContextMenuState {
  position: ContextMenuPosition;
  habit: HabitWithStats;
  triggerElement: HTMLElement | null;
}

export function useHabitCardContextMenu() {
  const [menuState, setMenuState] = useState<HabitCardContextMenuState | null>(null);

  const openMenu = useCallback((event: React.MouseEvent, habit: HabitWithStats) => {
    event.preventDefault();
    const triggerElement = event.currentTarget instanceof HTMLElement ? event.currentTarget : null;
    setMenuState({ position: { x: event.clientX, y: event.clientY }, habit, triggerElement });
  }, []);

  const closeMenu = useCallback(() => {
    setMenuState(null);
  }, []);

  return {
    menuState,
    openMenu,
    closeMenu,
  };
}
