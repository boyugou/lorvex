export function isCollapsedSectionKeyArray(value: unknown): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === 'string');
}

export function readCollapsedSectionSet(storedKeys: readonly string[]): Set<string> {
  return new Set(storedKeys);
}

export function serializeCollapsedSectionSet(collapsed: ReadonlySet<string>): string[] {
  return [...collapsed];
}

export function toggleCollapsedSection(
  collapsed: ReadonlySet<string>,
  key: string,
): Set<string> {
  const next = new Set(collapsed);
  if (next.has(key)) {
    next.delete(key);
  } else {
    next.add(key);
  }
  return next;
}

export function collapseAllSections(keys: readonly string[]): Set<string> {
  return new Set(keys);
}

export function expandAllSections(): Set<string> {
  return new Set<string>();
}
