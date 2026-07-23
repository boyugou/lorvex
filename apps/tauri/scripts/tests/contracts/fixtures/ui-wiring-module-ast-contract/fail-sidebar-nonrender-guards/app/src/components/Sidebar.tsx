function canShowModule(_moduleId: string) {
  return true;
}

const ALL_GUARDS = [
  canShowModule('today'),
  canShowModule('upcoming'),
  canShowModule('all_tasks'),
  canShowModule('someday'),
  canShowModule('calendar'),
  canShowModule('eisenhower'),
  canShowModule('daily_review'),
  canShowModule('memory'),
  canShowModule('review'),
  canShowModule('changelog'),
  canShowModule('focus'),
];

export function Sidebar() {
  return ALL_GUARDS.length > 0 ? null : null;
}
