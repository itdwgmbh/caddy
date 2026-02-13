FROM crvp-nbg1-01.itinfra.cloud/dhi/golang:1.26 AS builder

WORKDIR /src

RUN go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

RUN xcaddy build \
    --with github.com/digilolnet/caddy-bunny-ip

RUN printf 'package main\nimport ("net/http"; "os"; "time")\nfunc main() { c := &http.Client{Timeout: 2 * time.Second}; r, err := c.Get("http://localhost:2019/config/"); if err != nil || r.StatusCode != 200 { os.Exit(1) } }\n' > /tmp/healthcheck.go && \
    go build -o /tmp/healthcheck /tmp/healthcheck.go

FROM crvp-nbg1-01.itinfra.cloud/dhi/debian-base:trixie

COPY --from=builder --chown=1000:1000 /src/caddy /usr/bin/caddy
COPY --from=builder --chown=1000:1000 /tmp/healthcheck /usr/local/bin/healthcheck

EXPOSE 80 443 2019

ENV TZ=Europe/Berlin \
    XDG_DATA_HOME=/data \
    XDG_CONFIG_HOME=/config

HEALTHCHECK --interval=5s --timeout=10s --start-period=15s --retries=12 \
    CMD ["healthcheck"]

CMD ["/usr/bin/caddy", "run", "--config", "/etc/caddy/Caddyfile"]