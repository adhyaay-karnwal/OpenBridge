# Embedded Web Specification

## 1. Technology Stack

- Build: `yarn` + `rspack`
- Language/UI: TypeScript + React
- Styling: Tailwind CSS
- Quality: `oxlint` + `prettier` + `tsc`

Single source of truth for entrypoints and output paths is `web/rspack.config.js`.

## 2. Embedded WebView Surfaces

- `chat` entry: `src/embedded/chat/index.tsx`
- `preview` entry: `src/embedded/preview/index.tsx`

Embedded outputs are written into macOS resources:

- `macos/OpenBridge/Helpers/WebKitBridgeUI/WebKitBridgeResources/ChatAssets/`
- `macos/OpenBridge/Helpers/WebKitBridgeUI/WebKitBridgeResources/PreviewAssets/`

Development:

- `yarn serve:chat` (port 8083)
- `yarn serve:preview` (port 8085)

## 3. Swift ⇄ JavaScript OpenBridge

Embedded entrypoints must import the JSBridge client before using `window.jsb`.

```ts
await window.jsb.MessagesBridge.sendMessage('hello');
```

```ts
const unsub = window.jsb.MessagesBridge.onHistoryMessageAdded(message => {
  // handle event
});
```

OpenBridge payload types are consumed from `@/jsb`, aliased to:

- `../macos/JSBridge/index.d.ts`

Schema changes in Swift bridge types must be mirrored in embedded UI logic.

## 4. Build and Quality Commands

```bash
yarn build:embedded
yarn lint
yarn lint:fix
yarn typecheck
yarn test
```
