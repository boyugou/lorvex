// Re-export the shared cap so the frontend and backend stay in
// lockstep — the canonical value lives in `@lorvex/shared/validation`
// (mirroring `lorvex-domain/src/validation/limits.rs`). Local
// re-declaration would create silent drift between the spinner cap
// and the IPC validation; routing through the shared export keeps
// the two surfaces single-sourced.
export { MAX_ESTIMATED_MINUTES } from '@lorvex/shared/validation';
import { MAX_ESTIMATED_MINUTES } from '@lorvex/shared/validation';

export function estimatedMinutesDraftValue(value: number | null): string {
  return value != null ? String(value) : '';
}

export function estimatedMinutesDraftChanged(previous: number | null, next: number | null): boolean {
  return previous !== next;
}

export function parseEstimatedMinutesInput(value: string): number | null {
  const trimmed = value.trim();
  if (!trimmed) return null;
  if (!/^\d+$/.test(trimmed)) return null;
  const parsed = Number(trimmed);
  if (parsed <= 0 || parsed > MAX_ESTIMATED_MINUTES) return null;
  return parsed;
}

export function resolveEstimatedMinutesDraftState(value: string): {
  hasValidValue: boolean;
  invalid: boolean;
  parsed: number | null;
} {
  const parsed = parseEstimatedMinutesInput(value);
  return {
    parsed,
    invalid: value.trim().length > 0 && parsed === null,
    hasValidValue: parsed != null,
  };
}
