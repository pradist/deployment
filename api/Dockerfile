# ============================================================
# Stage 1 – Build (Go toolchain image)
# ============================================================
FROM golang:1.24-alpine AS builder

# Install git (needed by `go mod download` for private deps)
RUN apk add --no-cache git ca-certificates

WORKDIR /app

# Cache dependency layer (invalidated only when go.mod/go.sum change)
COPY go.mod go.sum ./
COPY vendor/ vendor/

# Copy source and build a static binary (use vendor — no network needed)
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -mod=vendor -ldflags="-w -s" -o /server .

# ============================================================
# Stage 2 – Runtime (minimal scratch image)
# ============================================================
FROM scratch

# Trust system CA certificates (copied from builder)
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy the static binary only
COPY --from=builder /server /server

# Non-root uid (scratch has no user management; set via numeric id)
USER 65534

EXPOSE 8080

ENTRYPOINT ["/server"]
