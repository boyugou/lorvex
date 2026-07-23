/**
 * Shared query timing constants for TanStack Query configuration.
 * Centralizes magic numbers that were scattered across 30+ files.
 */

/** 15 seconds — for frequently-changing data (focus session, timers). */
export const STALE_SHORT = 15_000;

/** 30 seconds — default for most entity queries (tasks, lists, events). */
export const STALE_DEFAULT = 30_000;

/** 60 seconds — for rarely-changing data (preferences, setup status). */
export const STALE_LONG = 60_000;

/** 60 seconds — Today surface refetch interval. */
export const TODAY_SURFACE_REFETCH_MS = 60_000;

/** 60 seconds — standard background refetch for entity lists. */
export const REFETCH_INTERVAL = 60_000;

export const STALE_5_MIN = 5 * 60 * 1000;

/** Milliseconds per day (86,400,000). */
export const MS_PER_DAY = 86_400_000;
