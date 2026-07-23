type TaskPriorityShortcut = 1 | 2 | 3;

export function priorityFromKeyboardKey(key: string): TaskPriorityShortcut | null {
  switch (key) {
    case '1':
      return 1;
    case '2':
      return 2;
    case '3':
      return 3;
    default:
      return null;
  }
}
