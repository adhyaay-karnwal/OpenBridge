#!/usr/bin/env bash
set -euo pipefail

# Build a complete Debian trixie rootfs with systemd and vmd for fly-vault VMs.
# Produces a tar.gz suitable for fly-vault provisioning (--rootfs flag).
#
# Requirements: Docker (with buildx for linux/amd64 cross-build)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="$(dirname "$SCRIPT_DIR")"
DIST_DIR="${AGENT_DIR}/dist"
DOCKER_CTX="${SCRIPT_DIR}/remote-rootfs"
OUTPUT="${DIST_DIR}/remote-rootfs.tar.gz"

mkdir -p "$DIST_DIR"

# Step 1: Cross-compile vmd for linux/amd64
echo "==> Building vmd for linux/amd64..."
cd "$AGENT_DIR"
GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -o "${DOCKER_CTX}/vmd" ./cmd/vmd

# Step 2: Build the Docker image
echo "==> Building remote rootfs image..."
TAG="remote-rootfs-$(date -u +%Y%m%d-%H%M%S)"
docker build --platform linux/amd64 -t "openbridge-remote-rootfs:${TAG}" "$DOCKER_CTX"

# Step 3: Export the container filesystem as tar.gz
echo "==> Exporting rootfs..."
CID=$(docker create "openbridge-remote-rootfs:${TAG}")
docker export "$CID" | gzip > "$OUTPUT"
docker rm "$CID" > /dev/null

# Clean up the vmd binary from the Docker context
rm -f "${DOCKER_CTX}/vmd"

echo "==> Remote rootfs: ${OUTPUT} ($(du -h "$OUTPUT" | cut -f1))"
