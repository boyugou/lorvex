/** Returns a small emoji prefix for event_type, or empty string for regular events. */
export function eventTypeIcon(eventType: string | undefined): string {
  switch (eventType) {
    case 'birthday': return '🎂 ';
    case 'anniversary': return '💍 ';
    case 'memorial': return '🕯 ';
    default: return '';
  }
}
