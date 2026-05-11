# syntax=docker/dockerfile:1
#
# Remote rootfs for fly-vault VMs.
# Based on Debian trixie with systemd, plus the vmd sandbox daemon.
#
FROM debian:trixie

ENV container=docker
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG DEBIAN_FRONTEND=noninteractive

# Install systemd + a practical base userland.
# Includes tools needed by the sandbox environment:
# - git, curl, wget for development workflows
# - python3 for the python tool
# - tmux for interactive reattachment
# - openssh-server for SSH access
# - util-linux for setsid, procps for ps
# - overlayfs-tools for sandbox overlay management
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus dbus-user-session \
      ca-certificates curl wget gnupg \
      iproute2 iputils-ping net-tools \
      openssh-server sudo \
      vim-tiny less procps util-linux tmux \
      python3 python3-pip \
      git rsync tar gzip \
      kmod udev \
      locales tzdata zstd xz-utils && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Locale
RUN sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# Mask units that are meaningless or problematic inside fly-vault containers.
RUN systemctl mask \
      dev-hugepages.mount \
      sys-fs-fuse-connections.mount \
      sys-kernel-config.mount \
      sys-kernel-debug.mount \
      sys-kernel-tracing.mount \
      getty.target \
      console-getty.service \
      systemd-remount-fs.service \
      systemd-logind.service || true

# Download Codex
RUN curl -fL https://github.com/openai/codex/releases/download/rust-v0.114.0/codex-x86_64-unknown-linux-gnu.zst | \
    zstd -d > /usr/local/bin/codex; chmod +x /usr/local/bin/codex && /usr/local/bin/codex --version

# Download Linear CLI
RUN mkdir -p /tmp/linear && cd /tmp/linear && \
    curl -fL https://github.com/schpet/linear-cli/releases/download/v1.11.1/linear-x86_64-unknown-linux-gnu.tar.xz | xz -d | tar x && \
    cp ./linear-x86_64-unknown-linux-gnu/linear /usr/bin/ && \
    cd / && rm -rf /tmp/linear

# Create workspace and sandbox directories used by vmd.
RUN mkdir -p /mnt/workspace /mnt/sandbox

# Install the pre-built vmd binary.
COPY vmd /usr/local/bin/vmd
RUN chmod +x /usr/local/bin/vmd

# Install the vmd systemd service.
COPY vmd.service /etc/systemd/system/vmd.service
RUN systemctl enable vmd.service

CMD ["/sbin/init"]
