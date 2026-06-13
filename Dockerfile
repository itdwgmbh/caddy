FROM alpine:3.24.0

ARG TARGETARCH

RUN apk add --no-cache ca-certificates tzdata

COPY --chown=1000:1000 caddy-linux-${TARGETARCH} /usr/bin/caddy
COPY --chown=1000:1000 healthcheck-${TARGETARCH} /usr/local/bin/healthcheck
COPY --chown=1000:1000 cert-sanity-${TARGETARCH} /usr/local/bin/cert-sanity
COPY --chown=1000:1000 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chown=1000:1000 Caddyfile /etc/caddy/Caddyfile

EXPOSE 80 443 2019

ENV TZ=Europe/Berlin \
    XDG_DATA_HOME=/data \
    XDG_CONFIG_HOME=/config

HEALTHCHECK --interval=5s --timeout=10s --start-period=15s --retries=12 \
    CMD ["healthcheck"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/bin/caddy", "run", "--config", "/etc/caddy/Caddyfile"]
