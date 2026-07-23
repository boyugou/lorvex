export function getCurrentHHMM(timezone: string | undefined, now: Date): string {
  if (timezone) {
    try {
      const parts = new Intl.DateTimeFormat('en-US', {
        hour: '2-digit',
        minute: '2-digit',
        hour12: false,
        timeZone: timezone,
      }).formatToParts(now);
      const hour = parts.find((part) => part.type === 'hour')?.value ?? '00';
      const minute = parts.find((part) => part.type === 'minute')?.value ?? '00';
      return `${hour}:${minute}`;
    } catch {
      // Fall through to system local time on invalid timezone.
    }
  }

  return `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
}

export function addMinutesToTime(time: string, minutes: number): string {
  const parts = time.split(':').map(Number);
  const hour = parts[0] ?? 0;
  const minute = parts[1] ?? 0;
  const total = hour * 60 + minute + minutes;
  const nextHour = Math.floor(total / 60) % 24;
  const nextMinute = total % 60;
  return `${String(nextHour).padStart(2, '0')}:${String(nextMinute).padStart(2, '0')}`;
}
