import { useI18n } from '@/lib/i18n';
import { ContextMenu } from '../context-menu/ContextMenu';
import { TrashIcon } from '../ui/icons';
import type { HabitCardContextMenuState } from './useHabitCardContextMenu';

interface HabitContextMenuProps {
  menuState: HabitCardContextMenuState | null;
  onClose: () => void;
  onDelete: (habit: HabitCardContextMenuState['habit'], triggerElement: HTMLElement | null) => void;
}

export function HabitContextMenu({ menuState, onClose, onDelete }: HabitContextMenuProps) {
  const { t } = useI18n();

  if (!menuState) {
    return null;
  }

  return (
    <ContextMenu
      position={menuState.position}
      onClose={onClose}
      triggerElement={menuState.triggerElement}
      items={[
        {
          key: 'delete',
          label: t('habits.contextDelete'),
          icon: <TrashIcon className="w-4 h-4" />,
          danger: true,
          onSelect: () => {
            const target = menuState.habit;
            const trigger = menuState.triggerElement;
            onClose();
            onDelete(target, trigger);
          },
        },
      ]}
    />
  );
}
