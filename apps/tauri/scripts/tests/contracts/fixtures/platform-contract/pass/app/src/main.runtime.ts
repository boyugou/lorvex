interface MainRuntimeDocumentLike {
  documentElement: {
    setAttribute: (name: string, value: string) => void;
  };
}

interface MainDocumentRuntimeDeps {
  desktopPlatform: string;
  documentTarget: MainRuntimeDocumentLike;
  mobilePlatform: string;
}

export function installMainDocumentRuntime(deps: MainDocumentRuntimeDeps): void {
  deps.documentTarget.documentElement.setAttribute('data-desktop-os', deps.desktopPlatform);
  deps.documentTarget.documentElement.setAttribute('data-mobile-os', deps.mobilePlatform);
}
