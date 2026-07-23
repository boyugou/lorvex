function parseNumber(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  return null;
}

export function evaluateMetadata(caseName: string, payload: Record<string, unknown>): {
  ok: boolean;
  note: string;
  limit: number | null;
  returned: number | null;
  totalMatching: number | null;
  truncated: boolean | null;
} {
  const limit = parseNumber(payload.limit);
  const returned = parseNumber(payload.returned ?? payload.count ?? payload.total_tasks);
  const totalMatching = parseNumber(payload.total_matching);
  const truncatedRaw = payload.truncated;
  const truncated = typeof truncatedRaw === 'boolean'
    ? truncatedRaw
    : typeof payload.any_truncated === 'boolean'
      ? payload.any_truncated
      : null;

  if (caseName === 'get_todays_tasks') {
    const summary = payload.summary as Record<string, unknown> | undefined;
    const summaryTotal = parseNumber(summary?.total);
    const summaryReturned = parseNumber(summary?.total_returned);
    if (summaryTotal === null || summaryReturned === null) {
      return { ok: false, note: 'missing summary.total/summary.total_returned', limit, returned, totalMatching, truncated };
    }
    const anyTruncated = Boolean(payload.any_truncated);
    const bucket = payload.truncated as Record<string, unknown> | undefined;
    const derivedAny = Boolean(bucket?.overdue) || Boolean(bucket?.today_tasks) || Boolean(bucket?.high_priority_undated);
    const ok = summaryReturned <= (parseNumber(payload.limit_per_bucket) ?? Number.MAX_SAFE_INTEGER) * 3
      && totalMatching === summaryTotal
      && returned === summaryReturned
      && anyTruncated === derivedAny;
    return {
      ok,
      note: ok ? 'ok' : 'todays summary/any_truncated mismatch',
      limit: parseNumber(payload.limit_per_bucket),
      returned,
      totalMatching,
      truncated: anyTruncated,
    };
  }

  if (caseName === 'get_upcoming_tasks') {
    const totalTasks = parseNumber(payload.total_tasks);
    const ok = returned !== null
      && totalMatching !== null
      && totalTasks !== null
      && returned === totalTasks
      && truncated !== null
      && truncated === (totalMatching > returned);
    return { ok, note: ok ? 'ok' : 'upcoming returned/truncated mismatch', limit, returned, totalMatching, truncated };
  }

  if (caseName === 'get_list') {
    const ok = limit !== null
      && returned !== null
      && totalMatching !== null
      && truncated !== null
      && returned <= limit
      && truncated === (totalMatching > returned);
    return { ok, note: ok ? 'ok' : 'get_list returned/truncated mismatch', limit, returned, totalMatching, truncated };
  }

  const ok = limit !== null
    && returned !== null
    && totalMatching !== null
    && truncated !== null
    && returned <= limit
    && truncated === (totalMatching > returned);
  return { ok, note: ok ? 'ok' : 'limit/returned/truncated mismatch', limit, returned, totalMatching, truncated };
}
