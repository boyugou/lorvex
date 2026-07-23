import { MS_PER_DAY } from '@/lib/query/timing';

// Returns 84 YYYY-MM-DD strings, oldest first, ending on todayYmd.
export function generateLast84Days(todayYmd: string): string[] {
  const today = new Date(todayYmd + 'T00:00:00Z');
  const dates: string[] = [];
  for (let i = 83; i >= 0; i--) {
    const d = new Date(today.getTime() - i * MS_PER_DAY);
    dates.push(d.toISOString().slice(0, 10));
  }
  return dates;
}
