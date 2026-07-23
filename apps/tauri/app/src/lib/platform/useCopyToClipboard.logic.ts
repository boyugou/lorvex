export interface ClipboardCopyHost {
  notifyCopyingChange: (copying: boolean) => void;
  notifyError: (error: unknown, fallbackMessage: string) => void;
  notifySuccess: (message: string) => void;
  writeText: (text: string) => Promise<void>;
}

interface ClipboardCopyController {
  copy: (text: string, successMessage?: string) => Promise<boolean>;
  isCopying: () => boolean;
}

export function createClipboardCopyController(
  host: ClipboardCopyHost,
  getDefaultSuccessMessage: () => string,
  getDefaultErrorMessage: () => string,
): ClipboardCopyController {
  let copying = false;

  return {
    copy: async (text, successMessage) => {
      if (copying) return false;
      copying = true;
      host.notifyCopyingChange(true);
      try {
        await host.writeText(text);
        host.notifySuccess(successMessage ?? getDefaultSuccessMessage());
      } catch (error) {
        host.notifyError(error, getDefaultErrorMessage());
      } finally {
        copying = false;
        host.notifyCopyingChange(false);
      }
      return true;
    },
    isCopying: () => copying,
  };
}
