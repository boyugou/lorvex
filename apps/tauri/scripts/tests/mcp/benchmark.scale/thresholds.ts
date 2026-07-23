/**
 * Performance budget thresholds for scale benchmarks.
 *
 * Each tool has a per-dataset-size ceiling in milliseconds. These are generous
 * enough to pass on any dev machine (debug binary, cold cache) but will catch
 * catastrophic regressions (e.g., missing index, N+1 query, O(n²) loop).
 *
 * Thresholds are defined for the 1000-task dataset. For larger datasets,
 * the threshold scales linearly: budget_ms(N) = base * (N / 1000).
 */

/** Base budget in ms for 1000 tasks (debug binary). */
const BASE_BUDGETS: Record<string, number> = {
  list_tasks: 500,
  search_tasks: 500,
  get_deferred_tasks: 500,
  get_todays_tasks: 300,
  get_upcoming_tasks: 500,
  get_list: 500,
};

/** Default budget for tools not explicitly listed. */
const DEFAULT_BUDGET_MS = 1000;

/**
 * Maximum regression factor before the benchmark fails.
 *
 * with REGRESSION_FACTOR = 1.0 there is zero headroom for
 * CI noise. A GitHub Actions runner sharing CPU with an adjacent job
 * can trivially double a 300 ms query time without any real regression.
 * 2.0× gives enough margin to absorb that noise while still catching
 * real O(n²) / missing-index / N+1 regressions (which typically blow
 * budgets by 5–100×, not 1.5×).
 */
const REGRESSION_FACTOR = 2.0;

export interface ThresholdResult {
  tool: string;
  dataset_size: number;
  elapsed_ms: number;
  budget_ms: number;
  passed: boolean;
}

export function checkThreshold(
  tool: string,
  datasetSize: number,
  elapsedMs: number,
): ThresholdResult {
  const baseBudget = BASE_BUDGETS[tool] ?? DEFAULT_BUDGET_MS;
  const scaleFactor = Math.max(1, datasetSize / 1000);
  const budget = baseBudget * scaleFactor * REGRESSION_FACTOR;

  return {
    tool,
    dataset_size: datasetSize,
    elapsed_ms: elapsedMs,
    budget_ms: Math.round(budget),
    passed: elapsedMs <= budget,
  };
}
