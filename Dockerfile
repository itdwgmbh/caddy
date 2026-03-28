FROM debian:trixie-slim

ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates tzdata && rm -rf /var/lib/apt/lists/*

COPY --chown=1000:1000 caddy-linux-${TARGETARCH} /usr/bin/caddy
COPY --chown=1000:1000 healthcheck /usr/local/bin/healthcheck
COPY --chown=1000:1000 Caddyfile /etc/caddy/Caddyfile

EXPOSE 80 443 2019

ENV TZ=Europe/Berlin \
    XDG_DATA_HOME=/data \
    XDG_CONFIG_HOME=/config

HEALTHCHECK --interval=5s --timeout=10s --start-period=15s --retries=12 \
    CMD ["healthcheck"]

CMD ["/usr/bin/caddy", "run", "--config", "/etc/caddy/Caddyfile"]
