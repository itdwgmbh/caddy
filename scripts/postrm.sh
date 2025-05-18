#!/bin/sh
set -e

# Reload systemd daemon
if [ -x "/bin/systemctl" ]; then
  systemctl daemon-reload || true
fi

# Only remove user/group and data directory on purge
if [ "$1" = "purge" ]; then
  # Remove caddy user and group
  if getent passwd caddy >/dev/null; then
    userdel caddy || true
  fi

  if getent group caddy >/dev/null; then
    groupdel caddy || true
  fi

  # Remove data directory
  rm -rf /var/lib/caddy || true
fi
