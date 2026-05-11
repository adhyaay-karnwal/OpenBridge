# AGENTS.md

Guidance for coding agents working in `web/`.

## Scope

`web/` contains only React/TypeScript assets embedded in the macOS app:

- `src/embedded/chat`
- `src/embedded/preview`
- shared `src/assets` and `src/utils`

Do not add standalone website, admin dashboard, auth, payment, or backend-proxy surfaces here.

## Commands

- `yarn install --immutable`
- `yarn build:embedded`
- `yarn serve:chat`
- `yarn serve:preview`
- `yarn lint`
- `yarn typecheck`
- `yarn test`

## Conventions

- Use yarn for package management.
- Use rspack for bundling.
- Use oxlint and prettier for code quality.
- Use Tailwind CSS for styling.
- Keep WebView contracts compatible with the Swift JSBridge client.
