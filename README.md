# Caddy (IT-DW)

A custom [Caddy](https://caddyserver.com) build bundling the IT-DW plugins:
DNS-01 via acme-dns (IT-DW DNS API), OIDC authentication, rate limiting, and
an S3 static-content proxy. Packaged on Alpine with a healthcheck and a
pre-start certificate sanity sweep.

Images are published to `ghcr.io/itdwgmbh/caddy` for `linux/amd64` and
`linux/arm64`, tagged `latest`, the upstream Caddy version (e.g. `v2.11.2`),
and the commit SHA.

## Running

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

The image ships a default `/etc/caddy/Caddyfile` that imports `sites-enabled/*`.
Mount your own `Caddyfile` to override it.

## Bundled modules

### acmedns — ACME DNS-01

Stock [`caddy-dns/acmedns`](https://github.com/caddy-dns/acmedns) provider
for DNS-01 challenges against the IT-DW DNS API's acme-dns endpoint. The
credential is a per-name acme-dns registration; mint it with
`itdw-api acme register --name <fqdn> --format caddy` and paste the output:

```caddyfile
app.kunde.de {
    tls {
        dns acmedns {
            username   {env.ACMEDNS_USERNAME}
            password   {env.ACMEDNS_PASSWORD}
            subdomain  {env.ACMEDNS_SUBDOMAIN}
            server_url https://dns-api.itinfra.cloud
        }
    }
    reverse_proxy backend:8080
}
```

One registration covers the apex cert, the wildcard cert, and the combined
apex+wildcard order for its name. The credential authorizes exactly one
challenge record — safe to deploy on hosts outside IT-DW control.

### caddy-oidc — OIDC authentication

Authorization Code flow with PKCE, opinionated towards Authentik. Keeps a
stateless session (verified ID token in an HttpOnly cookie) and forwards
claims to the upstream as `X-Auth-*` headers — no session store or signing
secret to manage.

```caddyfile
app.example.com {
    oidc {
        issuer        https://auth.example.com/application/o/myapp/
        client_id     {env.OIDC_CLIENT_ID}
        client_secret {env.OIDC_CLIENT_SECRET}
        allowed_groups admins   # optional: restrict to group members
    }
    reverse_proxy backend:8080
}
```

### caddy-ratelimit — HTTP rate limiting

Sliding-window rate limiting with multiple zones, request matchers, and
CIDR-based key grouping for IPv6.

```caddyfile
rate_limit {
    zone per_ip {
        key             {remote_host}
        events          100
        window          1m
        ipv6_prefix_len 64   # group an IPv6 /64 under one limiter
    }
}
```

### caddy-s3proxy — S3 static content

Serves static content from S3-compatible storage with AWS Signature V4 auth and Range-request support.

```caddyfile
docs.example.com {
    s3proxy {
        endpoint   https://s3.example.org
        bucket     docs-site
        region     eu1
        access_key {env.S3_ACCESS_KEY}
        secret_key {env.S3_SECRET_KEY}
        browse        # optional directory listing
    }
}
```

## Build

Images build automatically on push to `main`, monthly, and on manual trigger.
Each build resolves the latest upstream Caddy release and compiles it with
`xcaddy` plus the bundled plugins.
