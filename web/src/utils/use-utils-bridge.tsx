import { useEffect, useState } from 'react';
import { hasNativeJSBridge } from './bridge-runtime';

type Unsubscribe = () => void;
export type AppearanceMode = 'light' | 'dark';

const resolveMediaQueryAppearanceMode = (): AppearanceMode => {
  if (typeof window === 'undefined') {
    return 'dark';
  }

  return window.matchMedia?.('(prefers-color-scheme: dark)').matches
    ? 'dark'
    : 'light';
};

const bindBridgeValue = <T,>(opts: {
  get: () => Promise<T>;
  subscribe: (listener: (value: T) => void) => Unsubscribe;
  set: (value: T) => void;
}): Unsubscribe => {
  let received = false;

  // Get initial value, but don't overwrite if we already received a push update.
  opts
    .get()
    .then(value => {
      if (!received) opts.set(value);
    })
    .catch(() => {});

  const unsub = opts.subscribe(value => {
    received = true;
    opts.set(value);
  });

  return () => {
    received = true;
    unsub();
  };
};

/**
 * Subscribe to debug mode changes
 * @returns {boolean} - The current debug mode
 */
export const useUtilsBridgeDebugMode = () => {
  const [debugMode, setDebugMode] = useState(false);

  useEffect(() => {
    if (!hasNativeJSBridge()) {
      return;
    }
    const bridge = window.jsb.UtilsBridge;
    return bindBridgeValue({
      get: () => bridge.isDebugMode(),
      subscribe: listener => bridge.onSetDebugMode(listener),
      set: setDebugMode,
    });
  }, []);

  return debugMode;
};

/**
 * Subscribe to accent background color changes
 * @returns {object} - The current accent color
 * @returns {string} - The current accent background color in hex format
 * @returns {string} - The current accent foreground color in hex format
 */
export const useUtilsBridgeAccentColor = () => {
  const [backgroundColor, setBackgroundColor] = useState('34C759');
  const [foregroundColor, setForegroundColor] = useState('FFFFFF');

  useEffect(() => {
    if (!hasNativeJSBridge()) {
      return;
    }
    const unsubs = [] as Unsubscribe[];
    const bridge = window.jsb.UtilsBridge;
    unsubs.push(
      bindBridgeValue({
        get: () => bridge.getAccentBackgroundColor(),
        subscribe: listener => bridge.onSetAccentBackgroundColor(listener),
        set: setBackgroundColor,
      })
    );
    unsubs.push(
      bindBridgeValue({
        get: () => bridge.getAccentForegroundColor(),
        subscribe: listener => bridge.onSetAccentForegroundColor(listener),
        set: setForegroundColor,
      })
    );

    return () => {
      unsubs.forEach(unsub => unsub());
    };
  }, []);

  return {
    backgroundColor,
    foregroundColor,
  };
};

/**
 * Subscribe to appearance mode changes
 * @returns {'light' | 'dark'} - The resolved appearance mode
 */
export const useUtilsBridgeAppearanceMode = () => {
  const [appearanceMode, setAppearanceMode] = useState<AppearanceMode>(
    resolveMediaQueryAppearanceMode()
  );

  useEffect(() => {
    if (
      typeof window === 'undefined' ||
      typeof window.matchMedia !== 'function'
    ) {
      return;
    }

    const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
    const handleChange = (event: MediaQueryList | MediaQueryListEvent) => {
      setAppearanceMode(event.matches ? 'dark' : 'light');
    };

    handleChange(mediaQuery);

    if (typeof mediaQuery.addEventListener === 'function') {
      mediaQuery.addEventListener('change', handleChange);
      return () => mediaQuery.removeEventListener('change', handleChange);
    }

    mediaQuery.addListener(handleChange);
    return () => mediaQuery.removeListener(handleChange);
  }, []);

  return appearanceMode;
};

/**
 * Subscribe to language changes
 * @returns {string} - The current language
 */
export const useUtilsBridgeLanguage = () => {
  const [language, setLanguage] = useState(
    typeof navigator === 'undefined' ? 'en' : navigator.language || 'en'
  );

  useEffect(() => {
    if (!hasNativeJSBridge()) {
      return;
    }
    const bridge = window.jsb.UtilsBridge;
    return bindBridgeValue({
      get: () => bridge.getLanguage(),
      subscribe: listener => bridge.onSetLanguage(listener),
      set: setLanguage,
    });
  }, []);

  return language;
};

/**
 * Subscribe to username changes
 * @returns {string} - The current username
 */
export const useUtilsBridgeUsername = () => {
  const [username, setUsername] = useState('');

  useEffect(() => {
    if (!hasNativeJSBridge()) {
      return;
    }
    const bridge = window.jsb.UtilsBridge;
    return bindBridgeValue({
      get: () => bridge.getUsername(),
      subscribe: listener => bridge.onSetUsername(listener),
      set: setUsername,
    });
  }, []);

  return username;
};

let cachedMacosVersion: number | null = null;
/**
 * Get the macOS major version
 */
export const useMacosVersion = () => {
  const [macosVersion, setMacosVersion] = useState<number | null>(
    cachedMacosVersion
  );

  useEffect(() => {
    if (cachedMacosVersion || !hasNativeJSBridge()) return;
    window.jsb.UtilsBridge.getMacOSMajorVersion()
      .then(version => {
        cachedMacosVersion = version;
        setMacosVersion(version);
      })
      .catch(() => {});
  }, []);

  return macosVersion;
};
