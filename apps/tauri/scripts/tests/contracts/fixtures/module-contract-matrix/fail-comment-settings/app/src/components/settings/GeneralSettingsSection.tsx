const SIDEBAR_MODULE_OPTIONS = [
  { id: 'today' },
  { id: 'upcoming' },
  { id: 'all_tasks' },
  { id: 'someday' },
  { id: 'calendar' },
  { id: 'eisenhower' },
  { id: 'daily_review' },
  { id: 'memory' },
  { id: 'changelog' },
  { id: 'focus' },
  // { id: 'review' }
];

export default function GeneralSettingsSection() {
  return SIDEBAR_MODULE_OPTIONS.length > 0 ? null : null;
}
