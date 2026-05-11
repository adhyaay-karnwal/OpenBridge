#!/usr/bin/env zsh
# Create (idempotently) a local self-signed code-signing identity so that
# every rebuild of ComputerUse.app shares the same leaf certificate. macOS
# TCC keys ad-hoc signed apps by cdhash (which changes on every build) but
# keys identity-signed apps by the designated requirement bound to the leaf
# cert, which stays stable — so Accessibility / Input Monitoring / Screen
# Recording grants survive rebuilds.

set -euo pipefail

IDENTITY="${COMPUTERUSE_SIGN_IDENTITY:-ComputerUseNext dev}"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"
TRANSIT_PASS="computerusenext-dev-transit"

if security find-identity -v -p codesigning "${KEYCHAIN}" 2>/dev/null | grep -q "\"${IDENTITY}\""; then
    echo "signing identity \"${IDENTITY}\" already present — nothing to do"
    exit 0
fi

echo "creating self-signed code-signing identity: ${IDENTITY}"

workdir=$(mktemp -d)
trap 'rm -rf "${workdir}"' EXIT

cat > "${workdir}/openssl.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = v3_req

[dn]
CN = ${IDENTITY}

[v3_req]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

openssl req -x509 -newkey rsa:2048 \
    -keyout "${workdir}/key.pem" -out "${workdir}/cert.pem" \
    -days 3650 -nodes \
    -config "${workdir}/openssl.cnf" \
    2>/dev/null

# `-legacy` forces RC2/3DES-based PKCS12, which the macOS `security` CLI
# understands; OpenSSL 3's modern default uses PBMAC that `security` rejects.
openssl pkcs12 -export -legacy \
    -out "${workdir}/cert.p12" \
    -inkey "${workdir}/key.pem" \
    -in "${workdir}/cert.pem" \
    -passout "pass:${TRANSIT_PASS}" \
    -name "${IDENTITY}"

# -T /usr/bin/codesign partitions the private key so that codesign doesn't
# need an interactive keychain-access prompt on first use.
security import "${workdir}/cert.p12" \
    -k "${KEYCHAIN}" \
    -T /usr/bin/codesign \
    -P "${TRANSIT_PASS}"

echo ""
echo "identity installed:"
security find-identity -v -p codesigning "${KEYCHAIN}" | grep -- "${IDENTITY}" || true

cat <<EOF

Next steps:
  1. Run 'just bundle-app' — the first codesign may surface a one-time
     keychain-access dialog; click "Always Allow".
  2. Run 'just install-app' and then grant permissions once
     (\`.build/debug/ComputerUse permissions grant accessibility\`).
  3. From now on, rebuilds share the same designated requirement
     (identifier "com.computerusenext.ComputerUse" anchored to the
     "${IDENTITY}" leaf), so TCC grants persist across rebuilds.
EOF
