import type { TranslationKey } from '@/lib/i18n';
import type { Priority } from '@lorvex/shared/types';
import { PRIORITY_COLORS } from '@/components/task-card/support';

export type QuickDateOption = 'none' | 'today' | 'tomorrow' | 'weekend' | 'next-week' | 'custom';

// Renamed from `PRIORITY_OPTIONS` — the same name in
// `task-card/support.ts` is the central numeric/string pair used by
// the FilterDropdown contract; quick-capture carries extra fields
// (color + ariaLabelKey) so it stays a sibling rather than folding
// into the central registry, but the name now signals scope.
export const QUICK_CAPTURE_PRIORITY_OPTIONS: { value: Priority; label: string; color: string; ariaLabelKey: TranslationKey }[] = [
  { value: 1, label: 'P1', color: PRIORITY_COLORS[1], ariaLabelKey: 'task.priorityP1' },
  { value: 2, label: 'P2', color: PRIORITY_COLORS[2], ariaLabelKey: 'task.priorityP2' },
  { value: 3, label: 'P3', color: PRIORITY_COLORS[3], ariaLabelKey: 'task.priorityP3' },
];

export const DURATION_PRESET_VALUES = [15, 30, 60, 120, 240] as const;
