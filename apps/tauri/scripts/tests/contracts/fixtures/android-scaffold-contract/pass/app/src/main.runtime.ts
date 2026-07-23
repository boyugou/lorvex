interface MainRuntimeDocumentElementLike {
  setAttribute: (name: string, value: string) => void;
}

interface MainRuntimeDocumentLike {
  documentElement: MainRuntimeDocumentElementLike;
}

interface MainDocumentRuntimeDeps {
  documentTarget: MainRuntimeDocumentLike;
  mobilePlatform: string;
}

export function installMainDocumentRuntime(deps: MainDocumentRuntimeDeps): void {
  deps.documentTarget.documentElement.setAttribute('data-mobile-os', deps.mobilePlatform);
}
