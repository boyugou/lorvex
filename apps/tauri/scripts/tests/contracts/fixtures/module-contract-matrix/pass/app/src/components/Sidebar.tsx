function canShowModule(_id: string): boolean {
  return true;
}

export default function Sidebar() {
  return (
    <div>
      {canShowModule('today') && null}
      {canShowModule('upcoming') && null}
      {canShowModule('all_tasks') && null}
      {canShowModule('someday') && null}
      {canShowModule('calendar') && null}
      {canShowModule('eisenhower') && null}
      {canShowModule('daily_review') && null}
      {canShowModule('memory') && null}
      {canShowModule('review') && null}
      {canShowModule('changelog') && null}
      {canShowModule('focus') && null}
    </div>
  );
}
