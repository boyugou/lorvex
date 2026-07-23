import type { TranslationKey } from '@/lib/i18n';
import { useI18n } from '@/lib/i18n';
import { Button } from '../ui/Button';
import { Tooltip } from '../ui/Tooltip';

interface AddTaskHeaderButtonProps {
  /** i18n key for the visible button label (e.g. `allTasks.addTask`). */
  labelKey: TranslationKey;
  /** i18n key for the tooltip caption (e.g. `allTasks.addTaskTooltip`). */
  tooltipKey: TranslationKey;
  onClick: () => void;
}

/**
 * Per-view "+ Add task" header button used in the top-right of every
 * entity-list view (AllTasks / Upcoming / Eisenhower / Kanban). The
 * structure (Tooltip + ghost Button + leading "+" glyph) was duplicated
 * verbatim across the four views; consolidating it here keeps the four
 * affordances visually identical and routes any future tweak through a
 * single component.
 */
export function AddTaskHeaderButton({ labelKey, tooltipKey, onClick }: AddTaskHeaderButtonProps) {
  const { t } = useI18n();
  return (
    <Tooltip label={t(tooltipKey)}>
      <Button variant="ghost" size="sm" onClick={onClick}>
        + {t(labelKey)}
      </Button>
    </Tooltip>
  );
}
