import type React from 'react';
import type { Task } from '@/lib/ipc/tasks/models';

import type { SavePatch, Translator } from '../shared';

export interface TaskSecondaryMetaFieldsProps {
  task: Task;
  locale: string;
  t: Translator;
  onSave: SavePatch;
  /** Optional slot rendered as a row at the bottom of the primary grid (e.g. defer control). */
  deferSlot?: React.ReactNode;
}

/**
 * Shared prop bag for the secondary-grid temporal field components
 * (`DueTimeField`, `RemindersField`). Each field component accepts a
 * subset of these props; the bag is unioned so the caller can spread
 * `...common` into any of them without re-typing per field.
 *
 * `locale` is the raw app locale — the `lib/dateLocale` helpers and
 * `formatNumber` resolve internally and route through their respective
 * memoized caches, so passing the raw value avoids redundant resolution.
 */
export interface TaskTemporalFieldsProps {
  locale: string;
  task: Task;
  t: Translator;
  onSave: SavePatch;
}

export interface TaskMetricsFieldsProps {
  task: Task;
  t: Translator;
  onSave: SavePatch;
}
