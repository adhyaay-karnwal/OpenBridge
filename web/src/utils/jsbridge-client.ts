// Initialize JSBridge event system (Swift → JS)
import { jsbEvents } from './jsb-events';
import { hasNativeJSBridge } from './bridge-runtime';

const jsbCallbacks = new Map<
  string,
  (success: boolean, ret?: string) => void
>();

const jsBridge = (
  window as {
    webkit?: {
      messageHandlers?: {
        jsb: {
          postMessage: (
            message: [
              string /* callId */,
              string /* bridgeName */,
              string /* method */,
              string /* args */,
            ]
          ) => void;
        };
      };
    };
  }
).webkit?.messageHandlers?.jsb;

(
  window as any as {
    __jsbCallback__: (data: {
      callId: string;
      success: boolean;
      ret: string;
    }) => void;
  }
).__jsbCallback__ = (data: {
  callId: string;
  success: boolean;
  ret?: string;
}) => {
  jsbCallbacks.get(data.callId)?.(data.success, data.ret);
  jsbCallbacks.delete(data.callId);
};

const jsBridgePostMessage = jsBridge?.postMessage.bind(jsBridge);

let callIdCounter = 0;

function generateCallId(): string {
  return `jsb_${Date.now()}_${callIdCounter++}`;
}

// Cache for bridge proxies (each bridge can have both methods and event subscriptions)
const bridgeCache = new Map<string, object>();

function createCombinedBridgeProxy(bridgeName: string) {
  return new Proxy(
    {},
    {
      get: (_, prop: string) => {
        // onXxx methods are event subscriptions (Swift → JS)
        if (prop.startsWith('on') && prop.length > 2) {
          const eventName = prop[2].toLowerCase() + prop.slice(3);
          return (listener: (data: unknown) => void) =>
            jsbEvents.on(`${bridgeName}.${eventName}`, listener);
        }
        // Other methods are JS → Swift calls
        return (...args: unknown[]): Promise<unknown> => {
          return new Promise((resolve, reject) => {
            bridgeReady();
            if (!jsBridgePostMessage) {
              resolve(undefined);
              return;
            }

            const callId = generateCallId();
            const jsonData = JSON.stringify(args);

            jsbCallbacks.set(callId, (success: boolean, ret?: string) => {
              if (!success) {
                reject(new Error(ret));
                return;
              }
              try {
                const result = success
                  ? ret
                    ? JSON.parse(ret)
                    : undefined
                  : null;
                resolve(result);
              } catch {
                reject(`Failed to parse JSON: ${ret}`);
              }
            });

            jsBridgePostMessage([callId, bridgeName, prop, jsonData]);
          });
        };
      },
    }
  );
}

window.jsb = new Proxy(
  {},
  {
    get: (_, name: string) => {
      if (!bridgeCache.has(name)) {
        bridgeCache.set(name, createCombinedBridgeProxy(name));
      }
      return bridgeCache.get(name);
    },
  }
) as typeof window.jsb;

let _bridgeReady = false;

export function bridgeReady() {
  if (_bridgeReady) {
    return;
  }
  _bridgeReady = true;
  if (!hasNativeJSBridge()) {
    return;
  }
  setTimeout(() => {
    (window as any).webkit.messageHandlers.openbridgeReady.postMessage(
      'complete'
    );
  }, 0);
}
