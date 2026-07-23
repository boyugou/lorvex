type View = { type: string };

function mapViewToSidebarModule(view: View): string | null {
  switch (view.type) {
    case 'today': return 'today';
    case 'upcoming': return 'upcoming';
    case 'all': return 'all_tasks';
    case 'someday': return 'someday';
    case 'calendar': return 'calendar';
    case 'eisenhower': return 'eisenhower';
    case 'daily_review': return 'daily_review';
    case 'memory': return 'memory';
    case 'review': return 'review';
    case 'changelog': return 'changelog';
    default: return null;
  }
}

function isDesktopOnlySecondaryView(view: View): boolean {
  return view.type === 'calendar'
    || view.type === 'eisenhower'
    || view.type === 'daily_review'
    || view.type === 'memory'
    || view.type === 'review'
    || view.type === 'changelog';
}

export default function App() {
  const view = { type: 'today' };
  return mapViewToSidebarModule(view) && isDesktopOnlySecondaryView(view) ? null : null;
}
