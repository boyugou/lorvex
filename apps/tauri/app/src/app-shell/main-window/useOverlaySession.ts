import { useCallback, useRef, useState } from 'react';

interface OverlaySession<T = void> {
  activeSession: number | null;
  close: (expectedSessionId?: number) => void;
  data: T | null;
  open: (data?: T) => void;
  visible: boolean;
}

export function useOverlaySession<T = void>(): OverlaySession<T> {
  const [visible, setVisible] = useState(false);
  const [data, setData] = useState<T | null>(null);
  const sessionRef = useRef(0);

  const open = useCallback((openData?: T) => {
    sessionRef.current += 1;
    setData(openData ?? null);
    setVisible(true);
  }, []);

  const close = useCallback((expectedSessionId?: number) => {
    if (expectedSessionId != null && sessionRef.current !== expectedSessionId) return;
    sessionRef.current += 1;
    setData(null);
    setVisible(false);
  }, []);

  return {
    activeSession: visible ? sessionRef.current : null,
    close,
    data,
    open,
    visible,
  };
}
