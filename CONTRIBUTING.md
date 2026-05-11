# Contributing to OpenBridge

Thanks for taking the time to improve OpenBridge. This project is a macOS-first local agent app with a SwiftUI shell, embedded React WebViews, vendored `kwwk`, and a Go sandbox VM runtime.

## Development Setup

Start from the root `README.md` quickstart. The usual local loop is:

```bash
git submodule update --init --recursive
```

```bash
cd web
yarn install --immutable
yarn build:embedded
```

```bash
cd ../sandbox-vm
make framework
```

```bash
cd ../macos
BUILD_CONFIGURATION=UnsignedDebug bash DevKit/Scripts/workspace_build_debug.sh
```

## Before Opening a Pull Request

Run the checks that match the files you changed:

```bash
make check
```

```bash
cd web
yarn lint
yarn typecheck
yarn test
yarn build:embedded
```

```bash
cd sandbox-vm
make go-test
```

```bash
cd macos
bash DevKit/Scripts/workspace_test_unit.sh
```

If a check cannot run on your machine, mention that in the PR with the error or missing prerequisite.

## Code Guidelines

- Keep `kwwk` broadly useful as an agent SDK. Avoid adding OpenBridge-specific business concepts to it unless they are general SDK primitives.
- Prefer small, focused changes with clear ownership boundaries.
- Keep SwiftUI state explicit and use Swift concurrency for asynchronous work.
- Keep embedded WebView code in `web/src/embedded` and shared bridge utilities in `web/src/utils`.
- Keep sandbox VM behavior in `sandbox-vm`; Swift should not directly manipulate VM overlay state.
- Do not commit generated build products, local credentials, DerivedData, app bundles, or VM images.

## Pull Request Notes

Please include:

- What changed and why.
- How you tested it.
- Screenshots or short recordings for visible UI changes.
- Any follow-up work or known gaps.

## Security

Do not open public issues or PRs containing secrets, tokens, private keys, account identifiers, or unreleased vulnerability details. Use `SECURITY.md` for reporting security issues.
