# Caddy (IT-DW)

Custom Caddy build with DNS providers, OIDC authentication, rate limiting, S3 proxy, and tailnet identity.

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
            api_url    https://api.tailc6b0d.ts.net
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

### caddy-oidc

OIDC authentication middleware, opinionated towards Authentik. Runs the Authorization Code flow with PKCE, keeps a stateless session (verified ID token in an HttpOnly cookie), and forwards user claims to the upstream as `X-Auth-*` headers. No session store or signing secret to manage.

```caddyfile
# Minimal — protect a site, forward identity to the upstream
app.example.com {
    oidc {
        issuer        https://auth.example.com/application/o/myapp/
        client_id     {env.OIDC_CLIENT_ID}
        client_secret {env.OIDC_CLIENT_SECRET}
    }
    reverse_proxy backend:8080
}

# Restrict access to members of an Authentik group
admin.example.com {
    oidc {
        issuer         https://auth.example.com/application/o/admin/
        client_id      {env.OIDC_CLIENT_ID}
        client_secret  {env.OIDC_CLIENT_SECRET}
        allowed_groups admins
    }
    reverse_proxy backend:8080
}
```

| Parameter        | Required | Default                  | Description                                                       |
|------------------|----------|--------------------------|-------------------------------------------------------------------|
| `issuer`         | yes      |                          | OIDC issuer URL (Authentik: provider base ending in `/o/<slug>/`) |
| `client_id`      | yes      |                          | OAuth2 client ID (supports `{env.*}` placeholders)                |
| `client_secret`  | yes      |                          | OAuth2 client secret (supports `{env.*}` placeholders)            |
| `scopes`         | no       | `openid email profile`   | Requested scopes; Authentik's `profile` already carries `groups`  |
| `callback_path`  | no       | `/oidc/callback`         | Path intercepted to complete the flow                             |
| `redirect_url`   | no       | derived from request     | Pin the external callback URL instead of deriving it per request  |
| `cookie_name`    | no       | `oidc_session`           | Session cookie name                                               |
| `allowed_groups` | no       | (any authenticated user) | Restrict access to users in at least one of these groups          |
| `forward_claim`  | no       | `email`/`preferred_username`/`name`/`groups` → `X-Auth-*` | `<claim> <header>` pair, repeatable; replaces the defaults |

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

## Tailnet-only access

For internal services that must only be reachable over Tailscale, use Caddy's built-in `remote_ip` matcher — no custom plugin needed. The matcher tests `RemoteAddr` directly, so it is not fooled by an `X-Forwarded-For` rewrite from `trusted_proxies`:

```caddyfile
internal.example {
    @not_tailnet not remote_ip 100.64.0.0/10 fd7a:115c:a1e0::/48
    respond @not_tailnet 403
    reverse_proxy http://backend:8080
}
```

User identity now comes from TailID JWTs (see the `tailid` service), not from header injection.

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

## Pre-start cert sanity sweep

Caddy refuses to load a certificate whose stored public key doesn't match the
private key (`tls: private key does not match public key`) and the only
recovery is wiping the broken pair. The image's entrypoint runs `cert-sanity`
before `caddy run`, which walks `/data/caddy/certificates/*/*/<domain>.crt`,
compares each cert's public key to the matching `.key`, and removes any
`crt`/`key`/`json` triple that fails the check. Caddy then reissues on
startup instead of failing closed.

Override the storage root (for tests) with `CADDY_CERT_ROOT`.

## Build

Images are built automatically on push to main, monthly on the 10th, and on manual trigger. Both amd64 and arm64 are cross-compiled with xcaddy and packaged in an Alpine 3.23 image.

Tagged as `latest`, the upstream Caddy version (e.g. `v2.11.2`), and the git SHA.
