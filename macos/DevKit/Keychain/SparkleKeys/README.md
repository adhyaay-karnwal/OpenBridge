# Sparkle Signing Keys

This directory stores the Sparkle EdDSA keys used for signing macOS update archives.

- `private-key.txt`: Base64-encoded Ed25519 private seed. **Keep this file secret**; anyone with access can
  sign malicious updates.
- `public-key.txt`: Base64-encoded Ed25519 public key to embed in the app (`SUPublicEDKey`).

When rotating keys:

1. Remove existing key files in this directory.
2. Run `generate_keys` from Sparkle's `bin/` to generate a new pair.
3. Export the private key via `generate_keys -x <path>`.
4. Save the public key into `public-key.txt` and update `Info.plist`.
5. Commit the changes (private key should be tracked securely according to your repository policy).
