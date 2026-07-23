import type { TranslationKey } from '@/lib/i18n';

export function resolveTodayGreetingKey(currentTimeHHMM: string): TranslationKey {
  const match = /^(\d{2}):\d{2}$/.exec(currentTimeHHMM);
  if (!match) return 'greeting.morning';

  const hour = Number(match[1]);
  if (!Number.isInteger(hour) || hour < 0 || hour > 23) return 'greeting.morning';
  if (hour < 12) return 'greeting.morning';
  if (hour < 17) return 'greeting.afternoon';
  return 'greeting.evening';
}
