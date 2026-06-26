# Caddy (IT-DW)

A custom [Caddy](https://caddyserver.com) build bundling the IT-DW plugins:
DNS-01 via the IT-DW API, OIDC authentication, rate limiting, and an
S3 static-content proxy. Packaged on Alpine with a healthcheck and a
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

### caddy-dns-itdw — ACME DNS-01

DNS provider for DNS-01 challenges via the IT-DW API. Authenticates with an
Authentik-issued JWT via the OAuth2 `client_credentials` grant for a service
account (`client_id` + `username` + app-`password`). Provision a service
account in Authentik with a DNS grant covering the zones Caddy manages.

```caddyfile
{
    acme_dns itdw {
        client_id {env.ITDW_CLIENT_ID}
        username  {env.ITDW_USERNAME}
        password  {env.ITDW_PASSWORD}
    }
}
```

| Option       | Description                                              |
|--------------|----------------------------------------------------------|
| `client_id`  | Authentik OAuth2 client ID                               |
| `username`   | Service-account username                                 |
| `password`   | Service-account app-password                             |
| `api_url`    | API base URL (default `https://api.it-dw.com`)           |
| `token_url`  | Authentik token endpoint                                 |

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
