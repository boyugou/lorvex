const SIDEBAR_MODULE_OPTIONS = [
  { id: "today" },
  { id: "upcoming" },
  { id: "all_tasks" },
  { id: "someday" },
  { id: "calendar" },
  { id: "eisenhower" },
  { id: "daily_review" },
  { id: "memory" },
  // { id: "review" },
  { id: "changelog" },
  { id: "focus" },
] as const;

export function GeneralSettingsSection() {
  return SIDEBAR_MODULE_OPTIONS.length;
}
