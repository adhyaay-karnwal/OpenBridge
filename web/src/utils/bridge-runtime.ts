export function hasNativeJSBridge(): boolean {
  if (typeof window === 'undefined') {
    return false;
  }

  const webkitHandlers = (
    window as Window & {
      webkit?: {
        messageHandlers?: {
          jsb?: unknown;
          openbridgeReady?: unknown;
        };
      };
    }
  ).webkit?.messageHandlers;

  return !!(webkitHandlers?.jsb && webkitHandlers?.openbridgeReady);
}
