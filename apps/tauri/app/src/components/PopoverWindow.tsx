import PopoverWindowContent from './popover-window/PopoverWindowContent';
import { usePopoverWindowController } from './popover-window/usePopoverWindowController';

export default function PopoverWindow() {
  const controller = usePopoverWindowController();
  return <PopoverWindowContent controller={controller} />;
}
