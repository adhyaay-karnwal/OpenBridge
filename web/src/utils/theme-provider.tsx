import { useEffect } from 'react';
import {
  useUtilsBridgeAccentColor,
  useUtilsBridgeAppearanceMode,
} from './use-utils-bridge';
import { hasNativeJSBridge } from './bridge-runtime';
import { commitGlobalCSSVar } from '@/embedded/chat/global-css-var';

export const ThemeProvider = ({ children }: { children: React.ReactNode }) => {
  const { backgroundColor, foregroundColor } = useUtilsBridgeAccentColor();
  const appearanceMode = useUtilsBridgeAppearanceMode();

  useEffect(() => {
    commitGlobalCSSVar(
      'colorPrimary',
      backgroundColor ? `#${backgroundColor}` : undefined
    );

    commitGlobalCSSVar(
      'colorPrimaryHighlight',
      foregroundColor ? `#${foregroundColor}` : undefined
    );
  }, [backgroundColor, foregroundColor]);

  useEffect(() => {
    const root = document.documentElement;
    root.classList.toggle('dark', appearanceMode === 'dark');
    root.dataset.theme = appearanceMode;
    root.dataset.surfaceRuntime = hasNativeJSBridge() ? 'native' : 'browser';
    root.style.colorScheme = appearanceMode;
  }, [appearanceMode]);

  return children;
};
