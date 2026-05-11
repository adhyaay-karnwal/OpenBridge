# Development

The web project is located in the [web](../../web) directory. There are two ways to start development:

- `yarn dev:chat`  
  Uses the `--watch` flag to build assets into [ChatAssets](../OpenBridge/Helpers/WebKitBridgeUI/WebKitBridgeResources/ChatAssets/).  
  In [ChatWebView](../OpenBridge/Interface/WebViews/ChatWebView.swift), it will first try to load `chat.html` from this location.  
  If it’s not found, it will attempt to load `http://localhost:8083`.

  > ⚠️ When using this approach, every time you modify the web code, you’ll need to rebuild OpenBridge to update the bundled output.

- `yarn serve:chat`  
  Starts a dev server at [http://localhost:8083](http://localhost:8083), allowing you to mock APIs directly in the browser.

  > You must delete the files under [ChatAssets](../OpenBridge/Helpers/WebKitBridgeUI/WebKitBridgeResources/ChatAssets/) to use this mode.  
  > This approach supports hot-reloading. If the **native** part of the code hasn’t changed, you don’t need to rebuild.

## Developer Tools

Right-click inside the webview to access the `Inspect Element` option.
