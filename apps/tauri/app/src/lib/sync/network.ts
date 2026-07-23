import { readBrowserNavigatorConnection } from './network.runtime';

export interface NetworkCadenceHints {
  lowBandwidth: boolean;
  saveData: boolean;
}

export interface NavigatorConnectionLike {
  effectiveType?: string;
  saveData?: boolean;
  addEventListener?: (type: 'change', listener: () => void) => void;
  removeEventListener?: (type: 'change', listener: () => void) => void;
}

export function getNavigatorConnection(): NavigatorConnectionLike | null {
  return readBrowserNavigatorConnection();
}

export function readNetworkCadenceHints(): NetworkCadenceHints {
  const connection = getNavigatorConnection();
  const effectiveType = typeof connection?.effectiveType === 'string'
    ? connection.effectiveType.toLowerCase()
    : '';
  const lowBandwidth = effectiveType === 'slow-2g' || effectiveType === '2g';
  return {
    lowBandwidth,
    saveData: connection?.saveData === true,
  };
}
