import { reportClientError } from '../errors/errorLogging';
import type { Task } from '@/lib/ipc/tasks/models';
import { restoreTaskDeferral } from '@/lib/ipc/tasks/mutations/deferral';
import type { DeferralSnapshot } from '@/lib/ipc/tasks/mutations/deferral';
import { toast } from '../notifications/toast';

type DeferrableTask = Pick<
  Task,
  'id' | 'planned_date' | 'defer_count' | 'last_deferred_at' | 'last_defer_reason'
>;

type ToastAction = {
  label: string;
  onClick: () => void | Promise<void>;
};

type ClientErrorLevel = 'debug' | 'info' | 'warn' | 'error';

interface DeferralUndoDeps {
  restoreTaskDeferral: typeof restoreTaskDeferral;
  successToast: (message: string, action?: ToastAction, context?: string) => void;
  infoToast: (message: string, context?: string) => void;
  errorWithDetailToast: typeof toast.errorWithDetail;
  reportClientError: typeof reportClientError;
}

const runtimeDeps: DeferralUndoDeps = {
  restoreTaskDeferral,
  successToast: toast.success,
  infoToast: (message, context) => toast.info(message, context),
  errorWithDetailToast: toast.errorWithDetail,
  reportClientError,
};

let deps: DeferralUndoDeps = runtimeDeps;

interface TaskDeferralWithUndoOptions {
  task: DeferrableTask;
  runDefer: () => Promise<unknown>;
  invalidate: () => void;
  afterForwardSuccess?: (() => void) | undefined;
  afterSuccessToast?: (() => void) | undefined;
  successMessage: string;
  successToast?: DeferralUndoDeps['successToast'] | undefined;
  undoLabel: string;
  undoSuccessMessage?: string | undefined;
  reportForwardError?: ((error: unknown) => void) | undefined;
  onForwardError?: ((error: unknown) => void) | undefined;
  forwardErrorSource: string;
  forwardErrorMessage: string;
  forwardErrorToastMessage: string;
  forwardErrorDetails?: string | undefined;
  forwardErrorLevel?: ClientErrorLevel | undefined;
  reportUndoError?: ((error: unknown) => void) | undefined;
  undoErrorSource: string;
  undoErrorMessage: string;
  undoErrorToastMessage: string;
  undoErrorDetails?: string | undefined;
  undoErrorLevel?: ClientErrorLevel | undefined;
}

export function captureDeferralSnapshot(task: DeferrableTask): DeferralSnapshot {
  return {
    planned_date: task.planned_date,
    defer_count: task.defer_count,
    last_deferred_at: task.last_deferred_at,
    last_defer_reason: task.last_defer_reason,
  };
}

export async function runTaskDeferralWithUndo({
  task,
  runDefer,
  invalidate,
  afterForwardSuccess,
  afterSuccessToast,
  successMessage,
  successToast,
  undoLabel,
  undoSuccessMessage,
  reportForwardError,
  onForwardError,
  forwardErrorSource,
  forwardErrorMessage,
  forwardErrorToastMessage,
  forwardErrorDetails,
  forwardErrorLevel,
  reportUndoError,
  undoErrorSource,
  undoErrorMessage,
  undoErrorToastMessage,
  undoErrorDetails,
  undoErrorLevel,
}: TaskDeferralWithUndoOptions): Promise<void> {
  const snapshot = captureDeferralSnapshot(task);
  try {
    await runDefer();
    invalidate();
    afterForwardSuccess?.();
    const showSuccessToast = successToast ?? deps.successToast;
    showSuccessToast(successMessage, {
      label: undoLabel,
      onClick: async () => {
        try {
          await deps.restoreTaskDeferral(task.id, snapshot);
          invalidate();
          if (undoSuccessMessage) {
            deps.infoToast(undoSuccessMessage, task.id);
          }
        } catch (undoError) {
          if (reportUndoError) {
            reportUndoError(undoError);
          } else {
            deps.reportClientError(
              undoErrorSource,
              undoErrorMessage,
              undoError,
              undoErrorDetails,
              undoErrorLevel,
            );
          }
          deps.errorWithDetailToast(undoError, undoErrorToastMessage);
        }
      },
    }, task.id);
    afterSuccessToast?.();
  } catch (error) {
    if (reportForwardError) {
      reportForwardError(error);
    } else {
      deps.reportClientError(
        forwardErrorSource,
        forwardErrorMessage,
        error,
        forwardErrorDetails,
        forwardErrorLevel,
      );
    }
    deps.errorWithDetailToast(error, forwardErrorToastMessage);
    onForwardError?.(error);
  }
}

export const __TEST_ONLY__ = {
  setDepsForTests(overrides: Partial<DeferralUndoDeps>): void {
    deps = {
      ...runtimeDeps,
      ...overrides,
    };
  },
  resetDepsForTests(): void {
    deps = runtimeDeps;
  },
};
