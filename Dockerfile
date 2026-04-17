FROM alpine:3.23

ARG TARGETARCH

RUN apk add --no-cache ca-certificates tzdata

COPY --chown=1000:1000 caddy-linux-${TARGETARCH} /usr/bin/caddy
COPY --chown=1000:1000 healthcheck-${TARGETARCH} /usr/local/bin/healthcheck
COPY --chown=1000:1000 Caddyfile /etc/caddy/Caddyfile

EXPOSE 80 443 2019

ENV TZ=Europe/Berlin \
    XDG_DATA_HOME=/data \
    XDG_CONFIG_HOME=/config

HEALTHCHECK --interval=5s --timeout=10s --start-period=15s --retries=12 \
    CMD ["healthcheck"]

CMD ["/usr/bin/caddy", "run", "--config", "/etc/caddy/Caddyfile"]
