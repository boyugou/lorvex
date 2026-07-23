import type { Priority } from '@lorvex/shared/types';

export type PriorityFilterValue = Priority | null;

export function isPriority(value: unknown): value is Priority {
  return value === 1 || value === 2 || value === 3;
}

export function isPriorityOrNull(value: unknown): value is PriorityFilterValue {
  return value === null || isPriority(value);
}

export function parsePriorityFilterValue(value: string): PriorityFilterValue | undefined {
  switch (value) {
    case '':
      return null;
    case '1':
      return 1;
    case '2':
      return 2;
    case '3':
      return 3;
    default:
      return undefined;
  }
}
