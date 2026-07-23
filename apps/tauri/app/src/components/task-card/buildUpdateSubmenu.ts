import type { TranslationKey } from '@/lib/i18n';
import type { TaskUpdatePatch } from '@/lib/ipc/tasks/mutations/types';
import type { ContextMenuItem } from '../context-menu/ContextMenu';

type TFn = (key: TranslationKey) => string;
type TaskUpdateField = keyof TaskUpdatePatch;
type PresentTaskUpdateValue<K extends TaskUpdateField> = Exclude<TaskUpdatePatch[K], undefined>;

type RunUpdate = (
  updates: TaskUpdatePatch,
  source: string,
  errorMessage: string,
  successToast?: string,
) => void;

interface UpdateSubmenuOptions<K extends TaskUpdateField> {
  presets: Array<{ key: string; labelKey: TranslationKey; value: PresentTaskUpdateValue<K> }>;
  fieldName: K;
  source: string;
  errorMessage: string;
  successToast?: string | undefined;
  /** Append a date suffix (e.g. " 03-21") to preset labels. Only for string values. */
  dateSuffix?: boolean | undefined;
  /** Current field value -- presets matching this value are disabled. */
  currentValue?: PresentTaskUpdateValue<K> | null | undefined;
  /** If provided, a "clear" item is appended that nulls out the field. */
  clearItem?: {
    key: string;
    labelKey: TranslationKey;
    successToast?: string | undefined;
    errorMessage: string;
    updates?: TaskUpdatePatch | undefined;
  } | undefined;
}

function taskUpdateFieldPatch<K extends TaskUpdateField>(
  fieldName: K,
  value: PresentTaskUpdateValue<K>,
): TaskUpdatePatch {
  return { [fieldName]: value } as TaskUpdatePatch;
}

/**
 * Build a submenu from a preset array. Each preset maps to a menu item
 * whose onSelect calls `runUpdate` with `fieldName: preset.value`.
 */
export function buildUpdateSubmenu<K extends TaskUpdateField>(
  opts: UpdateSubmenuOptions<K>,
  t: TFn,
  runUpdate: RunUpdate,
): ContextMenuItem[] {
  const items: ContextMenuItem[] = opts.presets.map((preset) => {
    const baseLabel = t(preset.labelKey);
    const label = opts.dateSuffix && typeof preset.value === 'string'
      ? `${baseLabel}  ${preset.value.slice(5)}`
      : baseLabel;
    return {
      key: preset.key,
      label,
      disabled: opts.currentValue !== undefined && opts.currentValue === preset.value,
      onSelect: () => runUpdate(
        taskUpdateFieldPatch(opts.fieldName, preset.value),
        opts.source,
        opts.errorMessage,
        opts.successToast,
      ),
    };
  });

  const clearItem = opts.clearItem;
  if (clearItem) {
    // capture the narrowed reference once so the closure
    // uses the known-defined value instead of re-asserting `!` on a
    // field the type system already lost confidence in.
    items.push({
      key: clearItem.key,
      label: t(clearItem.labelKey),
      onSelect: () => runUpdate(
        clearItem.updates ?? taskUpdateFieldPatch(opts.fieldName, null as PresentTaskUpdateValue<K>),
        opts.source,
        clearItem.errorMessage,
        clearItem.successToast,
      ),
    });
  }

  return items;
}
