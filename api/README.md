# Go API — Code Overview (`main.go`)

## Architecture

```text
                          ┌─────────────────────────────────────────────────────────────┐
                          │                             main.go                         │
                          ├─────────────────────────────────────────────────────────────┤
  HTTP Request ──────────►│      gin.Logger ── gin.Recovery ── Prometheus Middleware    │
                          │                           │                                 │
                          │              ┌────────────┼────────────┐                    │
                          │              ▼            ▼            ▼                    │
                          │           /livez        /readyz      /metrics               │  ◄── Health & Observability
                          │           /             /items                              │  ◄── Business Routes
                          │              │            │                                 │
                          │              ▼            ▼                                 │
                          │           welcome()    getItems()                           │
                          │                           │                                 │
                          │                           ▼                                 │
                          │                    ┌──────────────┐                         │
                          │                    │ PostgreSQL   │                         │
                          │                    │  (db-service)│                         │
                          │                    └──────────────┘                         │
                          └─────────────────────────────────────────────────────────────┘

  Prometheus ──scrapes /metrics every 15s──► Grafana displays Dashboard
```

## Code Structure — 5 Sections

### 1. Prometheus Metrics — Collect Statistics

| Metric | Type | Purpose |
| ------ | ---- | ------- |
| `http_requests_total` | Counter | Counts all requests, labeled by method, path, and status |
| `http_request_duration_seconds` | Histogram | Measures how long each request takes (in seconds) |

The **Middleware** wraps every request like a checkpoint:

```text
Request arrives → Start timer → Handler runs → Record metric (count +1, save duration)
```

### 2. Database — PostgreSQL Connection

- Reads connection settings from **Environment Variables** (`DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`)
- Connection pool: max 25 open, 5 idle, connections expire after 5 minutes
- If the DB is unreachable, it logs a warning but does **not** crash (the API still works partially)

| Env Variable | Default | Description |
| ------------ | ------- | ----------- |
| `DB_HOST` | `localhost` | Database host address |
| `DB_PORT` | `5432` | Database port |
| `DB_USER` | `postgres` | Database username |
| `DB_PASSWORD` | `password` | Database password |
| `DB_NAME` | `appdb` | Database name |

### 3. Handlers — Request Handling

| Endpoint | Function | Purpose |
| -------- | -------- | ------- |
| `GET /livez` | `healthLive()` | Liveness probe — is the container still running? |
| `GET /readyz` | `healthReady()` | Readiness probe — is the app ready to serve traffic? (pings DB) |
| `GET /metrics` | promhttp | Exposes metrics for Prometheus to scrape |
| `GET /` | `welcome()` | Returns a welcome message with the current time |
| `GET /items` | `getItems()` | Fetches all items from the database |

**How Kubernetes uses Health Probes:**

```yaml
livenessProbe:   → /livez   → if it fails → Kubernetes restarts the Pod
readinessProbe:  → /readyz  → if it fails → Kubernetes stops sending traffic
```

### 4. Graceful Shutdown — Clean Exit

```text
Kubernetes sends SIGTERM
        │
        ▼
signal.Notify catches the signal
        │
        ▼
Stop accepting new requests
        │
        ▼
Wait for in-flight requests to finish (15s timeout)
        │
        ▼
Server shuts down cleanly
```

This prevents requests from being cut off mid-response when a Pod is scaled down or redeployed.

### 5. Server Configuration

| Setting | Default | Description |
| -------- | ------- | ----------- |
| `PORT` | `8080` | Port the server listens on |
| `GIN_MODE` | `release` | Gin framework mode |
| ReadTimeout | 10s | Max time to read an incoming request |
| WriteTimeout | 10s | Max time to write a response |
| IdleTimeout | 60s | How long to keep idle connections alive |

## Startup Flow

```text
1. main() starts
   │
   ├── initDB()              → Connect to PostgreSQL
   ├── Create Gin router     → Attach middleware (Logger, Recovery, Prometheus)
   ├── Register routes       → /livez, /readyz, /metrics, /, /items
   ├── Start HTTP server     → Runs in a separate goroutine
   │
   └── Wait for SIGTERM/SIGINT → Graceful Shutdown (15s timeout)
```
