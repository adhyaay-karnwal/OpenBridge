# OpenBridge Embedded Web

This package builds the React surfaces embedded inside the macOS app.

## Commands

```bash
yarn install --immutable
yarn build:embedded
yarn serve:chat
yarn serve:preview
yarn lint
yarn typecheck
yarn test
```

Embedded outputs are written to:

`../macos/OpenBridge/Helpers/WebKitBridgeUI/WebKitBridgeResources/`

## Source Layout

```
src/
├── assets/      # shared assets
├── embedded/    # chat, preview
└── utils/       # JSBridge and shared browser utilities
```
