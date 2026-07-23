import { formatNumber } from '@/locales';
import {
  reconcileTaskDraftField,
  type ReconcileTaskDraftFieldArgs,
  type ReconcileTaskDraftFieldResult,
} from './controller/drafts.logic';

export function buildChecklistProgressLabel(
  locale: string,
  completedCount: number,
  totalCount: number,
): string | null {
  if (totalCount <= 0) return null;
  return `${formatNumber(locale, completedCount)}/${formatNumber(locale, totalCount)}`;
}

export function reconcileChecklistItemDraft(
  args: ReconcileTaskDraftFieldArgs,
): ReconcileTaskDraftFieldResult {
  return reconcileTaskDraftField(args);
}
