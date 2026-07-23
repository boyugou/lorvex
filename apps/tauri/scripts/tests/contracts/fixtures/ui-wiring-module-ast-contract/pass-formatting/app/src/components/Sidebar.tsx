function canShowModule(_moduleId: string) {
  return true;
}

export function Sidebar() {
  const visible = [
    canShowModule("today"),
    canShowModule("upcoming"),
    canShowModule("all_tasks"),
    canShowModule("someday"),
    canShowModule("calendar"),
    canShowModule("eisenhower"),
    canShowModule("daily_review"),
    canShowModule("memory"),
    canShowModule("review"),
    canShowModule("changelog"),
    canShowModule("focus"),
  ];

  return visible.length;
}
