function mapViewToSidebarModule(view: { type: string }) {
  switch (view.type) {
    case "today":
      return "today";
    case "upcoming":
      return "upcoming";
    case "all":
      return "all_tasks";
    case "someday":
      return "someday";
    case "calendar":
      return "calendar";
    case "eisenhower":
      return "eisenhower";
    case "daily_review":
      return "daily_review";
    case "memory":
      return "memory";
    case "review":
      return "review";
    case "changelog":
      return "changelog";
    default:
      return null;
  }
}

export function App() {
  return mapViewToSidebarModule({ type: "today" });
}
