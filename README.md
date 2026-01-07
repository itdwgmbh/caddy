# Caddy Builder

Internal build pipeline for custom Caddy Docker images.

## Overview

This repository builds Caddy with the following plugins:
- [`caddy-bunny-ip`](https://github.com/digilolnet/caddy-bunny-ip) - Bunny CDN IP validation

Images are built monthly and pushed to the internal container registry with multi-architecture support (linux/amd64 and linux/arm64).

## Features

- Multi-stage builds with Alpine base image
- Automated monthly builds
- Multi-platform support (AMD64 and ARM64)
- Default configuration redirects all traffic to https://it-dw.com
- Health checks via Caddy admin API

## Usage

### Running the Container

With default configuration (redirects to https://it-dw.com):
```bash
docker run -d \
  -p 80:80 \
  -p 443:443 \
  ${ITDW_CONTAINER_REGISTRY_SERVER}/library/caddy:latest
```

With custom Caddyfile:
```bash
docker run -d \
  -p 80:80 \
  -p 443:443 \
  -v /path/to/Caddyfile:/etc/caddy/Caddyfile:ro \
  -v /path/to/data:/data \
  -v /path/to/config:/config \
  ${ITDW_CONTAINER_REGISTRY_SERVER}/library/caddy:latest
```

### Example Caddyfile

```caddyfile
{
    # Global options
    email admin@example.com
}

example.com {
    # Bunny CDN IP validation
    route {
        bunny_ip {
            # Your Bunny IP configuration
        }
    }

    # Your site configuration
    reverse_proxy localhost:8080
}
```

### Docker Compose Example

```yaml
services:
  caddy:
    image: ${ITDW_CONTAINER_REGISTRY_SERVER}/library/caddy:latest
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    restart: unless-stopped

volumes:
  caddy_data:
  caddy_config:
```

## Build Process

1. Builds Caddy with xcaddy including the specified plugins
2. Creates a minimal Alpine-based image with curl for health checks

## CI/CD

GitHub Actions workflow triggers:
- Manual trigger
- Monthly on the 15th at 12:21 UTC
- Push to main branch

Images are tagged with:
- `latest` - Most recent build
- Caddy version (e.g., `v2.9.1`)

The workflow connects to the internal network via Tailscale before pushing to the registry.

### Required GitHub Secrets

- `ITDW_CONTAINER_REGISTRY_SERVER`
- `ITDW_CONTAINER_REGISTRY_USER`
- `ITDW_CONTAINER_REGISTRY_PASSWORD`
- `TS_OAUTH_CLIENT_ID`
- `TS_OAUTH_SECRET`

### Ports

- `80` - HTTP
- `443` - HTTPS
- `2019` - Admin API (health checks)
