#!/bin/sh
set -e

# Stop service if running
if [ -x "/bin/systemctl" ]; then
  systemctl stop caddy || true
  systemctl disable caddy || true
fi
