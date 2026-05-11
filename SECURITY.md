# Security Policy

OpenBridge runs local agents that can read files, call tools, and execute commands in sandboxed or host environments. Security reports are taken seriously.

## Reporting a Vulnerability

Please do not disclose vulnerabilities publicly until they have been reviewed.

Report security issues by opening a private security advisory on GitHub if available for this repository. If advisories are not available, contact the maintainers through a private channel and include:

- Affected component: macOS app, WebView, provider auth, `kwwk`, sandbox VM, or CI/release infrastructure.
- Steps to reproduce.
- Impact and required permissions.
- Whether secrets, local files, sandbox boundaries, or host execution are involved.

## Sensitive Areas

Pay special attention to:

- Provider OAuth tokens and API keys.
- Application Support data under `~/.openbridge`.
- Sandbox VM mount configuration and accept/discard behavior.
- Tool permission flows for direct host access.
- WebView bridge messages crossing between React and Swift.
- CI workflows that use signing, release, or object storage credentials.

## Supported Versions

OpenBridge is under active development. Security fixes target `main` unless a release branch is explicitly maintained.
