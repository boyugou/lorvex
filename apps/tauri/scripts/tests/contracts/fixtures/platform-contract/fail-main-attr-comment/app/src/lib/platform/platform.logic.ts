export type DesktopPlatform = 'macos' | 'windows' | 'linux' | 'unknown';
export type MobilePlatform = 'android' | 'unknown';
export type RuntimeClass = 'desktop' | 'mobile' | 'unknown';
export type RuntimeId = 'macos' | 'windows' | 'linux' | 'android' | 'unknown';

export interface RuntimeNavigatorSnapshot {
  userAgent: string;
}

export interface RuntimeProfile {
  runtimeClass: RuntimeClass;
  runtimeId: RuntimeId;
  supportsBiometricLock: boolean;
  supportsTitleBarOverlay: boolean;
  supportedSyncBackendKinds: string[];
  supportsMcpHosting: boolean;
  trayPresentationKind: 'none' | 'menu_bar' | 'system_tray';
  supportsDesktopOverlays: boolean;
  supportsAssistantCommandPolling: boolean;
  supportsAutostart: boolean;
  supportsNativeCalendarRead: boolean;
  nativeCalendarAdapterKind: string;
  nativeCalendarActivationState: string;
}

export function detectMobilePlatform(snapshot: RuntimeNavigatorSnapshot | null): MobilePlatform {
  if (snapshot?.userAgent.includes('Android')) {
    return 'android';
  }
  return 'unknown';
}

export function detectDesktopPlatform(snapshot: RuntimeNavigatorSnapshot | null): DesktopPlatform {
  if (detectMobilePlatform(snapshot) !== 'unknown') {
    return 'unknown';
  }
  return 'macos';
}

export function buildRuntimeProfile(runtimeId: RuntimeId): RuntimeProfile {
  return {
    runtimeClass: 'desktop',
    runtimeId,
    supportsBiometricLock: true,
    supportsTitleBarOverlay: true,
    supportedSyncBackendKinds: ['remote_provider', 'filesystem_bridge'],
    supportsMcpHosting: true,
    trayPresentationKind: 'menu_bar',
    supportsDesktopOverlays: true,
    supportsAssistantCommandPolling: true,
    supportsAutostart: true,
    supportsNativeCalendarRead: true,
    nativeCalendarAdapterKind: 'eventkit',
    nativeCalendarActivationState: 'active',
  };
}
