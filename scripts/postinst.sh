#!/bin/sh
set -e

# Reload systemd daemon
systemctl daemon-reload || true

# Set appropriate permissions
if [ -d /var/lib/caddy ]; then
  chown -R caddy:caddy /var/lib/caddy
fi

# Create and set permissions for log directory
if [ -d /var/log/caddy ]; then
  chown -R caddy:caddy /var/log/caddy
  chmod 755 /var/log/caddy
fi

echo "Caddy has been installed!"
echo "To start Caddy, run: sudo systemctl enable --now caddy"
echo "To check status: sudo systemctl status caddy"
echo "Configuration file: /etc/caddy/Caddyfile"
echo "Admin API: http://127.0.0.1:2019"
echo "Metrics: http://127.0.0.1:2020"
echo "Logs: /var/log/caddy/"
