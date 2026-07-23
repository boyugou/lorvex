import type { RefObject } from 'react';
import { TaskDetailContent } from './task-detail/content';
import { type TaskDetailProps } from './task-detail/support';
import { useTaskDetailController } from './task-detail/controller/useTaskDetailController';

interface TaskDetailWithRefProps extends TaskDetailProps {
  /**
   * Forwarded to the title input so the enclosing SlidePanel can move
   * focus to it on open. Optional -- when omitted, the
   * panel falls back to focusing the panel element itself.
   */
  titleRef?: RefObject<HTMLInputElement | null>;
}

export default function TaskDetail(props: TaskDetailWithRefProps) {
  const { titleRef, ...controllerProps } = props;
  const controller = useTaskDetailController(controllerProps);
  return <TaskDetailContent controller={controller} titleRef={titleRef} />;
}
