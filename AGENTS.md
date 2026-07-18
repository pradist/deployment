# AGENTS.md

Deployment lab: Kubernetes + Go (Gin) API + Docker + Prometheus/Grafana + Hurl/k6 tests.
Primary environment is Google Cloud Shell; Minikube runs the cluster locally.

## Commands

- Run the local stack (Postgres + API + Prometheus + Grafana + node-exporter):
  `docker compose up --build` (compose DB password is `password`, not `postgres`)
- Full functional test suite (Hurl), default `dev` env:
  `make test` (== `hurl tests/hurl/*.hurl --variables-file ./hurl/env/dev.env --test`)
- Target a different env file: `make ENV=prod test` (copy `hurl/env/prod.env.example` to
  `hurl/env/prod.env` — gitignored — and set prod values)
- Run a single Hurl file: `hurl tests/hurl/items.hurl --variables-file ./hurl/env/dev.env --test`
- Go API build (uses vendored deps, needs `vendor/` committed):
  `cd api && go build -mod=vendor ./...`

## Key facts

- `api/` is the only Go module (`github.com/pradist2/deployment/api`). It builds a static
  binary from vendored deps (`-mod=vendor`); keep `vendor/` in sync via `go mod vendor`.
  Docker build is multi-stage with a `scratch` runtime — binary must be `GOOS=linux GOARCH=amd64`.
- DB connection is via env vars only: `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`.
  App connects by K8s Service name `db-service`, not IP. `/readyz` pings the DB; `/livez` does not.
- DB password is `password` everywhere: `docker-compose.yml`, and the k8s Secret
  `postgres-secret` (`POSTGRES_PASSWORD: cGFzc3dvcmQ=` = base64 of `password`).
  DB user is `postgres`, db name `appdb`.
- `k8s/api-deployment.yaml` ships `image: pradiske/go-api:latest` with a `TODO` placeholder —
  replace the repo (`sed -i "s|pradiske/go-api|${DOCKER_USERNAME}/go-api|"`) before `kubectl apply`.
  The image is pulled from Docker Hub at deploy time.
- No CI workflow or pre-commit config exists in this repo despite README mentioning GitHub Actions;
  CI runs on a self-hosted runner configured manually per the README.

## Tests

- Hurl is the functional test layer (`tests/hurl/`); k6 is the load test (`tests/k6/script.js`).
  Hurl needs a running stack and a matching `--variables-file` (`hurl/env/*.env`).
- `hurl/env/dev.env` points at `http://localhost:8080` with `admin_user=admin`, `admin_pass=admin1234`.

## References

- `README.md` — full lab walkthrough (setup, deploy, CI/CD).
- `api/README.md` — endpoint/architecture reference for the Go API.
- `TROUBLESHOOTING.md` — K8s/ImagePull/CrashLoop/runner fixes.
