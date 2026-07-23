export function MainViewContent({ view }: { view: { type: string } }) {
  if ("today" === view.type) return null;
  if ("upcoming" === view.type) return null;
  if ("all" === view.type) return null;
  if ("someday" === view.type) return null;
  if ("calendar" === view.type) return null;
  if ("eisenhower" === view.type) return null;
  if ("daily_review" === view.type) return null;
  if ("memory" === view.type) return null;
  if ("review" === view.type) return null;
  if ("changelog" === view.type) return null;
  return null;
}
