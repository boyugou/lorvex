/**
 * Layout constants for MonthGrid.
 *
 * Extracted from the original MonthGrid.tsx during the M29 split so
 * the desktop and mobile branches can share these values without each
 * pulling in the entire renderer module.
 */

/** Height of the date number + its bottom margin inside each cell (px). */
export const DATE_HEADER_PX = 32;
/** Height of each event/task item line (px). */
export const ITEM_LINE_PX = 18;
/** Minimum items to show even at small sizes. */
export const MIN_ITEMS = 2;
/** Cell vertical padding (p-2 = 8px top + 8px bottom). */
export const CELL_PAD_PX = 16;
