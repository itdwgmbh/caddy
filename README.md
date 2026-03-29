# Caddy (IT-DW)

Custom Caddy build with DNS providers, CDN IP validation, rate limiting, and S3 proxy.

Images are published to `ghcr.io/itdwgmbh/caddy` for linux/amd64 and linux/arm64.

## Included Modules

### caddy-bunny-ip

Validates that requests originate from [Bunny CDN](https://bunny.net) IP ranges. Used when Caddy sits behind Bunny as a pull zone to restore the real client IP.

```caddyfile
{
    servers {
        trusted_proxies bunny {
            interval 12h
            timeout 15s
        }
    }
}
```

### caddy-dns-itdw

DNS provider for ACME DNS-01 challenges via the IT-DW API. Authenticates with TailID JWT tokens over Tailscale — no API keys needed.

```caddyfile
# Global — all sites use IT-DW DNS for certificates
{
    acme_dns itdw
}

# Per-site
example.com {
    tls {
        dns itdw
    }
}

# With optional URL overrides
example.com {
    tls {
        dns itdw {
            api_url    https://api.tailc6b0d.ts.net
            tailid_url https://tailid.tailc6b0d.ts.net
        }
    }
}
```

Requires the Caddy instance to be on the Tailscale network.

### caddy-autodns

DNS provider for ACME DNS-01 challenges via the [AutoDNS](https://www.autodns.com) API (InterNetX). Context defaults to `8026211`.

```caddyfile
# Global
{
    acme_dns autodns {
        username {env.AUTODNS_USER}
        password {env.AUTODNS_PASS}
    }
}

# Per-site
example.com {
    tls {
        dns autodns {
            username {env.AUTODNS_USER}
            password {env.AUTODNS_PASS}
        }
    }
}

# All options
example.com {
    tls {
        dns autodns {
            username {env.AUTODNS_USER}
            password {env.AUTODNS_PASS}
            endpoint https://api.autodns.com/v1
            context  8026211
        }
    }
}
```

### caddy-ratelimit

HTTP rate limiting with sliding window. Supports multiple zones, request matchers, and CIDR-based key grouping for IPv6.

```caddyfile
# Basic — limit per client IP
rate_limit {
    zone per_ip {
        key    {remote_host}
        events 100
        window 1m
    }
}

# With IPv6 /64 grouping — all IPs in the same prefix share one limiter
rate_limit {
    zone per_network {
        key             {remote_host}
        events          200
        window          1m
        ipv6_prefix_len 64
        ipv4_prefix_len 24
    }
}

# Multiple zones with request matchers
rate_limit {
    zone api {
        key    {remote_host}
        events 60
        window 1m
        match {
            path /api/*
        }
    }
    zone global {
        key    {remote_host}
        events 300
        window 1m
    }
}
```

### caddy-s3proxy

Serves static content from S3-compatible storage (Hetzner Object Storage, Infomaniak) with AWS Signature V4 authentication. Supports Range requests for video/large files.

```caddyfile
# Serve a static site from Hetzner Object Storage
docs.example.com {
    s3proxy {
        endpoint   https://fsn1.your-objectstorage.com
        bucket     docs-site
        region     fsn1
        access_key {env.S3_ACCESS_KEY}
        secret_key {env.S3_SECRET_KEY}
    }
}

# Serve assets from a subfolder in the bucket
assets.example.com {
    s3proxy {
        endpoint   https://s3.pub1.infomaniak.cloud
        bucket     my-assets
        region     dc3-a
        access_key {env.S3_ACCESS_KEY}
        secret_key {env.S3_SECRET_KEY}
        root       public/assets
        index      index.html
    }
}
```

## Running

### Docker Compose

```yaml
services:
  caddy:
    image: ghcr.io/itdwgmbh/caddy:latest
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./sites-enabled:/etc/caddy/sites-enabled:ro
      - caddy_data:/data
      - caddy_config:/config
    restart: unless-stopped

volumes:
  caddy_data:
  caddy_config:
```

### Default Caddyfile

The built-in Caddyfile uses the IT-DW private ACME CA, Bunny CDN trusted proxies, and imports from `sites-enabled/`:

```caddyfile
{
    email support@it-dw.com
    acme_ca https://acme.tailc6b0d.ts.net/private/directory
    admin 0.0.0.0:2019

    log {
        level INFO
        output stdout
    }

    servers {
        trusted_proxies bunny {
            interval 12h
            timeout 15s
        }
    }
}

import sites-enabled/*
```

## Build

Images are built automatically on push to main, monthly on the 10th, and on manual trigger. Both amd64 and arm64 are cross-compiled with xcaddy and packaged in an Alpine 3.23 image.

Tagged as `latest`, the upstream Caddy version (e.g. `v2.11.2`), and the git SHA.
