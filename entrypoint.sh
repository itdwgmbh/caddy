#!/bin/sh
set -e

# Format all Caddyfiles before starting
echo "Formatting Caddyfile..."
caddy fmt --overwrite /etc/caddy/Caddyfile

# Execute the main command (passed as arguments)
exec "$@"
