export function parseRetentionDaysPreference(raw: string | null): number | null {
  if (raw == null) return null;
  const trimmed = raw.trim();
  if (!/^[1-9]\d*$/.test(trimmed)) return null;

  const parsed = Number(trimmed);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) return null;
  return parsed;
}
