export interface OptionalListIdInvalidationOptions {
  listId?: string | null | undefined;
}

export interface OptionalTaskAndListInvalidationOptions {
  taskId?: string;
  listId?: string | null;
}

export interface TaskDetailWriteTarget {
  id: string;
  list_id: string;
}

export interface TaskDetailWriteInvalidationOptions {
  extraListIds?: string[];
}

export interface TaskDependencyInvalidationOptions {
  taskId: string;
  relatedTaskId?: string | null;
}
