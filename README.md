# Caddy (IT-DW)

Custom [Caddy](https://caddyserver.com) for IT-DW edges. Bundles DNS-01 via
acme-dns (IT-DW DNS API), OIDC authentication, HTTP rate limiting, and an S3
static-content proxy.

Shipped as the container image `ghcr.io/itdwgmbh/caddy` (tags `latest`, the
upstream Caddy version, `sha-<commit>`) and as a `.deb` in the IT-DW APT
repository and downloads.

## Install (Debian / Ubuntu)

From the IT-DW APT repository (preferred on bare metal):

```bash
curl -fsSL https://itdwstatic.blob.core.windows.net/packages/gpg.pub | sudo gpg --dearmor -o /usr/share/keyrings/itinfra.gpg
echo "deb [signed-by=/usr/share/keyrings/itinfra.gpg] https://itdwstatic.blob.core.windows.net/packages/apt/ itdw-packages main" \
  | sudo tee /etc/apt/sources.list.d/itinfra.list
sudo apt update
sudo apt install caddy
```

Or download `caddy-amd64.deb` or `caddy-arm64.deb` from
`https://itdwstatic.blob.core.windows.net/packages/downloads/caddy/`.

Config lives at `/etc/caddy/Caddyfile` (`import sites-enabled/*`); drop site
configs into `/etc/caddy/sites-enabled/`. `caddy.service` runs that config
file; `caddy-api.service` runs `caddy run --resume` instead, reloading the
config last applied through the admin API. `dpkg -L caddy` lists every
installed path.

```bash
sudo systemctl enable --now caddy
sudo systemctl reload caddy
```

The package version is the upstream Caddy version plus `+itdw.<CI run number>`,
so plugin rebuilds of the same Caddy tag remain upgradeable via apt.

## Run (container)

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

The image's default `Caddyfile` binds the admin API on all interfaces and
imports `sites-enabled/*`; mount your own to override it. Do not publish the
admin port unless the admin API is meant to be reachable.

The entrypoint runs `cert-sanity` before Caddy: it drops any cert/key pair
whose public keys no longer match, which is otherwise a fatal load error Caddy
won't recover from on its own.

## Bundled modules

The `xcaddy build` step in `.github/workflows/build.yml` lists the modules.
Configuration is in each module's README:
[acmedns](https://github.com/caddy-dns/acmedns),
[caddy-oidc](https://github.com/itdwgmbh/caddy-oidc),
[caddy-ratelimit](https://github.com/itdwgmbh/caddy-ratelimit),
[caddy-s3proxy](https://github.com/itdwgmbh/caddy-s3proxy).

For DNS-01 against the IT-DW DNS API, mint a per-name acme-dns registration
with `itdw-api acme register --name <fqdn> --format caddy`:

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
challenge record, so it is safe to deploy on hosts outside IT-DW control.

## Build

Each run of `.github/workflows/build.yml` builds the latest upstream Caddy
release with every module from its current `main`, so a module change ships on
the next build with no change here. It publishes the image to GHCR and builds
the `.deb` packages; `packages.yml` then triggers
[package-factory](https://github.com/itdwgmbh/package-factory), which
publishes the downloads and the signed APT repository.

## Supply chain

Published images carry an SBOM and SLSA provenance attestation, a keyless
cosign signature, and a Trivy scan in the repo Security tab.

```bash
cosign verify \
  --certificate-identity-regexp 'https://github.com/itdwgmbh/caddy/.github/workflows/build.yml@.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/itdwgmbh/caddy@sha256:<digest>

docker buildx imagetools inspect ghcr.io/itdwgmbh/caddy:latest \
  --format '{{ json (index .SBOM "linux/amd64").SPDX }}'
```
