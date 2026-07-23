import type { Priority } from '@lorvex/shared/types';
import type { useI18n } from '@/lib/i18n';
import type { ParseResult } from '@/lib/dateParser';
import type { QuickDateOption } from '../types';

export interface CompactToolbarProps {
  // Date
  dateOption: QuickDateOption;
  customDate: string;
  setCustomDate: (date: string) => void;
  setDateOption: (option: QuickDateOption) => void;
  toggleDateOption: (option: QuickDateOption) => void;
  clearDate: () => void;
  // NL date
  activeNlDate: ParseResult | null;
  clearNlDate: () => void;
  // Priority
  priority: Priority | null;
  togglePriority: (value: Priority) => void;
  clearPriority: () => void;
  // Duration
  estimatedMinutes: string;
  setEstimatedMinutes: (value: string) => void;
  toggleDuration: (minutes: number) => void;
  clearDuration: () => void;
  // Tags
  tagsInput: string;
  setTagsInput: (value: string) => void;
  // i18n
  t: ReturnType<typeof useI18n>['t'];
}

export type CompactToolbarTranslate = CompactToolbarProps['t'];
