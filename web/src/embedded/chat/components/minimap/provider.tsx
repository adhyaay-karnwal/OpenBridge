import { createContext, useContext } from 'react';
import type { MinimapOptions } from './minimap';

const MinimapOptionsContext = createContext<MinimapOptions>({});

export const MinimapOptionsProvider = ({
  value,
  children,
}: {
  value: MinimapOptions;
  children: React.ReactNode;
}) => {
  return (
    <MinimapOptionsContext.Provider value={value}>
      {children}
    </MinimapOptionsContext.Provider>
  );
};

export const useMinimapOptions = () => useContext(MinimapOptionsContext);
