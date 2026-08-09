# Caddy (IT-DW)

Custom [Caddy](https://caddyserver.com) image for IT-DW edges. Bundles DNS-01 via
acme-dns (IT-DW DNS API), OIDC authentication, HTTP rate limiting, and an S3
static-content proxy. Packaged on Alpine with a Docker healthcheck and a
pre-start certificate sanity sweep.

Images: `ghcr.io/itdwgmbh/caddy` (`linux/amd64`, `linux/arm64`).

Tags: `latest`, upstream Caddy version (e.g. `v2.11.2`), and `sha-<commit>`.

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

The image ships a default `/etc/caddy/Caddyfile` that binds the admin API on
`[::]:2019` and imports `sites-enabled/*`. Mount your own `Caddyfile` to
override it. Do not publish port `2019` unless you intend to expose the admin API.

### Image extras

| Path | Role |
|---|---|
| `/usr/bin/caddy` | Custom Caddy with the modules below |
| `/usr/local/bin/healthcheck` | Docker `HEALTHCHECK` — `GET http://localhost:2019/config/` |
| `/usr/local/bin/cert-sanity` | Pre-start: drops cert/key pairs whose public keys do not match |
| `/usr/local/bin/entrypoint.sh` | Runs `cert-sanity`, then `exec`s Caddy |

## Bundled modules

### acmedns — ACME DNS-01

Stock [`caddy-dns/acmedns`](https://github.com/caddy-dns/acmedns) for DNS-01
against the IT-DW DNS API acme-dns endpoint. Mint a per-name registration with
`itdw-api acme register --name <fqdn> --format caddy`:

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

Authorization Code flow with PKCE, opinionated towards Authentik. Stateless
session (verified ID token in an HttpOnly cookie); claims forwarded upstream as
`X-Auth-*` headers — no session store or signing secret.

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

Static content from S3-compatible storage with AWS Signature V4 and Range
requests.

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

Images build on push to `main`, monthly (10th, 15:00 UTC), and on manual
dispatch. Each run:

- Resolves the **latest upstream Caddy release**
- Compiles with **latest stable Go** (`actions/setup-go` `stable`)
- Builds plugins from their current `main` via `xcaddy`
- Publishes multi-arch to GHCR

Plugin set:

- `github.com/caddy-dns/acmedns`
- `github.com/itdwgmbh/caddy-oidc`
- `github.com/itdwgmbh/caddy-ratelimit`
- `github.com/itdwgmbh/caddy-s3proxy`

## Supply chain

Every published image includes:

- **SBOM** — SPDX attestation from BuildKit (Syft)
- **Provenance** — SLSA provenance (`mode=max`) for the GitHub Actions build
- **Cosign** — keyless signature via the workflow OIDC identity (Sigstore)
- **Trivy** — post-push scan (`CRITICAL`/`HIGH`, fixed only); SARIF on the Security tab

```bash
cosign verify \
  --certificate-identity-regexp 'https://github.com/itdwgmbh/caddy/.github/workflows/build.yml@.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/itdwgmbh/caddy@sha256:<digest>

docker buildx imagetools inspect ghcr.io/itdwgmbh/caddy:latest \
  --format '{{ json (index .SBOM "linux/amd64").SPDX }}'
```
