import { parse } from 'partial-json';
import { useMemo } from 'react';

export const useParsePartialJson = (raw?: string) => {
  return useMemo(() => {
    if (!raw) {
      return null;
    }
    try {
      return parse(raw);
    } catch {
      return null;
    }
  }, [raw]);
};
