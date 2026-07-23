import SidebarContent from './sidebar/SidebarContent';
import { useSidebarController, type SidebarProps } from './sidebar/useSidebarController';

export default function Sidebar(props: SidebarProps) {
  const controller = useSidebarController(props);
  return <SidebarContent controller={controller} />;
}
