#!/bin/bash

set -e

cd "$(dirname $0)/kbuild"

mkdir -p ../../dist ../../resources/vm ../../../macos/OpenBridge/Resources

image_tag="$(date -u +%s)-$(openssl rand -hex 4)"
docker build -t "openbridge-kbuild:$image_tag" .
container_id="$(docker create "openbridge-kbuild:$image_tag")"
docker cp "$container_id:/opt/kernel.arm64" ../../dist/
docker rm "$container_id"
docker image rm "openbridge-kbuild:$image_tag"

cp ../../dist/kernel.arm64 ../../resources/vm/kernel.bin
cp ../../dist/kernel.arm64 ../../../macos/OpenBridge/Resources/kernel.bin
