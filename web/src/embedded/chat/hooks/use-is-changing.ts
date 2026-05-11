/* oxlint-disable react-hooks/exhaustive-deps */

import { useEffect, useRef, useState } from 'react';

/**
 * useIsChanging
 *
 * Tracks whether a given dependency (or multiple dependencies)
 * is currently "changing".
 *
 * When any dependency changes, the hook sets `isChanging` to `true`.
 * After the specified delay without further changes, it automatically
 * switches back to `false`.
 *
 * @param deps  The dependency array to watch
 * @param delay The delay (in milliseconds) before considering the value stable (default: 300)
 * @returns A boolean indicating whether the dependencies are currently changing
 */
export function useIsChanging(deps: any[], delay = 1000): boolean {
  const [isChanging, setIsChanging] = useState(false);
  const timerRef = useRef<number | null>(null);

  useEffect(() => {
    // Mark as changing immediately when dependencies update
    setIsChanging(true);

    // Clear the previous timeout if it exists
    if (timerRef.current) {
      clearTimeout(timerRef.current);
    }

    // Set a new timeout to mark as stable after the delay
    timerRef.current = window.setTimeout(() => {
      setIsChanging(false);
    }, delay);

    // Cleanup on unmount or before next effect run
    return () => {
      if (timerRef.current) {
        clearTimeout(timerRef.current);
      }
    };
  }, deps);

  return isChanging;
}
