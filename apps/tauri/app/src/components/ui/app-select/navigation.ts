import type { ParsedOption } from './model';

export function findNextEnabledOption(
  options: ParsedOption[],
  start: number,
  direction: 1 | -1,
): number {
  if (options.length === 0) return -1;
  for (let offset = 1; offset <= options.length; offset += 1) {
    const idx = (start + offset * direction + options.length) % options.length;
    if (!options[idx]!.disabled) {
      return idx;
    }
  }
  return -1;
}
