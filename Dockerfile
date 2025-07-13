# Multi-stage build for optimal size and build speed
# Using golang:alpine automatically gets the latest stable Go version
FROM golang:alpine AS builder

# Install build dependencies
RUN apk add --no-cache git ca-certificates tzdata

# Set working directory
WORKDIR /src

# Copy custom CA certificates
COPY custom-cas/*.crt /usr/local/share/ca-certificates/
RUN update-ca-certificates

# Install xcaddy for building custom Caddy
RUN go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest

# Build Caddy with custom modules
RUN xcaddy build \
    --with github.com/digilolnet/caddy-bunny-ip \
    --with github.com/greenpau/caddy-security

# Get Caddy version for tagging
RUN /src/caddy version | cut -d' ' -f1 > /src/caddy-version.txt

# Final stage - distroless root user for privileged ports
FROM gcr.io/distroless/static:latest

# Copy CA certificates from builder (includes system CAs)
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy binary from builder stage
COPY --from=builder /src/caddy /usr/bin/caddy

# Copy timezone data
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

# Copy default Caddyfile
COPY Caddyfile /etc/caddy/Caddyfile

# Expose standard ports (root user can bind to privileged ports)
EXPOSE 80 443 2019

# Health check (uses management port 2019)
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ["/usr/bin/caddy", "version"]

# Default command - configured for unprivileged ports
CMD ["/usr/bin/caddy", "run", "--config", "/etc/caddy/Caddyfile"]