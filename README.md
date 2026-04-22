# Caddy (IT-DW)

Custom Caddy build with DNS providers, rate limiting, S3 proxy, and tailnet identity.

Images are published to `ghcr.io/itdwgmbh/caddy` for linux/amd64 and linux/arm64.

## Included Modules

### caddy-dns-itdw

DNS provider for ACME DNS-01 challenges via the IT-DW API. Authenticates over Tailscale — no API keys needed.

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

# With optional URL override
example.com {
    tls {
        dns itdw {
            api_url    https://apvp-001.tailc6b0d.ts.net
        }
    }
}
```

Requires the Caddy instance to be on the Tailscale network.

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

# Browse bucket contents with directory listing
files.example.com {
    s3proxy {
        endpoint   https://fsn1.your-objectstorage.com
        bucket     shared-files
        region     fsn1
        access_key {env.S3_ACCESS_KEY}
        secret_key {env.S3_SECRET_KEY}
        browse
    }
}
```

| Parameter    | Required | Default      | Description                                              |
|--------------|----------|--------------|----------------------------------------------------------|
| `endpoint`   | yes      |              | S3-compatible endpoint URL                               |
| `bucket`     | yes      |              | Bucket name                                              |
| `region`     | no       | `auto`       | Bucket region                                            |
| `access_key` | yes      |              | S3 access key (supports `{env.*}` placeholders)          |
| `secret_key` | yes      |              | S3 secret key (supports `{env.*}` placeholders)          |
| `root`       | no       |              | Prefix prepended to all object keys                      |
| `index`      | no       | `index.html` | File served for directory requests                       |
| `browse`     | no       | `false`      | Show directory listing when index file is not found      |

### caddy-tailnet-identity

HTTP middleware that authenticates incoming requests against the local `tailscaled` socket and injects identity + capability headers for downstream handlers. Returns `401 Unauthorized` when the source IP can't be resolved to a tailnet node — useful for protecting internal services without per-service auth.

```caddyfile
example.com {
    tailnet_identity
    reverse_proxy http://backend:8080
}

# With explicit socket path
example.com {
    tailnet_identity {
        socket /var/run/tailscale/tailscaled.sock
    }
    reverse_proxy http://backend:8080
}
```

Every managed header is scrubbed from the incoming request unconditionally before authentication runs, so a client cannot pre-set them to spoof identity. On a successful whois, a subset is then repopulated:

| Header                 | Source                                                                          | When                                     |
|------------------------|---------------------------------------------------------------------------------|------------------------------------------|
| `Tailscale-Node-ID`    | `whois.Node.StableID`                                                           | always                                   |
| `Tailscale-Node-Name`  | `whois.Node.ComputedName`                                                       | always                                   |
| `Tailscale-Node-Tags`  | comma-joined `whois.Node.Tags`                                                  | when non-empty                           |
| `Tailscale-User-Login` | `whois.UserProfile.LoginName`                                                   | when caller is a user-owned device       |
| `Tailscale-User-Name`  | `whois.UserProfile.DisplayName`                                                 | same                                     |
| `Tailscale-Caps`       | `whois.CapMap` as single-line (compacted) JSON object (original keys preserved) | when non-empty                           |
| `Remote-User`          | alias of `Tailscale-User-Login`                                                 | same                                     |
| `Remote-Name`          | alias of `Tailscale-User-Name`                                                  | same                                     |

`Remote-User` / `Remote-Name` follow the forward-auth header convention used by Authelia, Authentik, Grafana `auth.proxy`, Jellyfin, etc., so apps that already speak that dialect work without Tailscale-specific config.

The Caddy container must have the host's `tailscaled` socket mounted:

```yaml
volumes:
  - /var/run/tailscale/tailscaled.sock:/var/run/tailscale/tailscaled.sock:ro
```

Authz pattern: backends read `Tailscale-Caps`, `json.Unmarshal` into `map[string]json.RawMessage`, and look up their own cap key (e.g. `"itdw.cloud/cap/mcp/easybill"`). Cap grants are sourced from the Tailscale ACL `grants` block — single source of truth, no per-service authz table.

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

The built-in Caddyfile uses the IT-DW private ACME CA and imports from `sites-enabled/`:

```caddyfile
{
	email support@it-dw.com
	acme_ca https://acme.itinfra.cloud/directory
	admin 0.0.0.0:2019

	log {
		level INFO
		output stdout
		exclude admin.api
	}
}

import sites-enabled/*
```

## Build

Images are built automatically on push to main, monthly on the 10th, and on manual trigger. Both amd64 and arm64 are cross-compiled with xcaddy and packaged in an Alpine 3.23 image.

Tagged as `latest`, the upstream Caddy version (e.g. `v2.11.2`), and the git SHA.
