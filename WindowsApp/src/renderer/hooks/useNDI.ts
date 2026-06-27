/**
 * Bootstrap hook — registers global NDI IPC listeners on mount and feeds
 * them into the Zustand store.  Call once at App root.
 */

import { useEffect } from 'react';
import { useAppStore } from '../store/appStore';

export function useNDIBootstrap(): void {
  const setSources = useAppStore((s) => s.setSources);
  const setTally   = useAppStore((s) => s.setTally);

  useEffect(() => {
    const offSources = window.ndiAPI.onSources(setSources);
    const offTally   = window.ndiAPI.onTally(setTally);

    return () => {
      offSources();
      offTally();
    };
  }, [setSources, setTally]);
}
