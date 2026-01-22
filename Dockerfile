# Multi-stage build for optimal size and build speed
# Using golang:alpine automatically gets the latest stable Go version
FROM golang:alpine AS builder

# Install build dependencies
RUN apk add --no-cache git ca-certificates tzdata

# Set working directory
WORKDIR /src

# Install xcaddy for building custom Caddy
RUN go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

# Build Caddy with custom modules
RUN xcaddy build \
    --with github.com/digilolnet/caddy-bunny-ip

# Final stage - Alpine for minimal size with shell access
FROM alpine:latest

# Install runtime dependencies
RUN apk add --no-cache ca-certificates tzdata curl

# Copy binary from builder stage
COPY --from=builder /src/caddy /usr/bin/caddy

# Copy default Caddyfile
COPY Caddyfile /etc/caddy/Caddyfile

# Copy and set up entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Expose standard ports (root user can bind to privileged ports)
EXPOSE 80 443 2019

# Health check using admin API
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ["curl", "-sf", "http://localhost:2019/config/"]

# Entrypoint formats Caddyfile before starting
ENTRYPOINT ["/entrypoint.sh"]

# Set ENV for Caddy
ENV XDG_DATA_HOME=/data
ENV XDG_CONFIG_HOME=/config

# Default command - configured for unprivileged ports
CMD ["/usr/bin/caddy", "run", "--config", "/etc/caddy/Caddyfile"]