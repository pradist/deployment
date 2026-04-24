# Production-Ready Deployment Lab

> **Total time ~2.5 hours** | Kubernetes · Go · Docker · GitHub Actions · Prometheus · Grafana · k6

## Repository Structure

```text
deployment/
├── .github/
│   └── workflows/
│       └── ci-cd.yml           # GitHub Actions CI/CD pipeline
├── api/
│   ├── main.go                 # Go (Gin) API with health probes + metrics
│   ├── go.mod
│   ├── Dockerfile              # Multi-stage build
│   └── .dockerignore
├── k8s/
│   ├── postgres-db.yaml        # PostgreSQL Deployment + Service + Secret
│   ├── api-deployment.yaml     # Go API Deployment + Service + HPA
│   ├── prometheus.yaml         # Prometheus + RBAC + ConfigMap
│   └── grafana.yaml            # Grafana + Datasource provisioning
├── tests/
│   ├── k6/
│   │   └── script.js           # k6 load test script
│   └── hurl/
│       └── api.hurl            # Hurl functional test
├── TROUBLESHOOTING.md          # Common errors & quick fixes
└── README.md                   # This guide
```

---

## Lab Environment – Google Cloud Shell

> This lab uses **Google Cloud Shell** as the primary environment — no local installation required.

### How to Access Google Cloud Shell

1. Open your browser and go to [https://ssh.cloud.google.com](https://ssh.cloud.google.com)
2. Sign in with your Google Account (a Google Cloud Project must be active)
3. Wait for the terminal to be ready (approximately 10–30 seconds)

### Verify Pre-installed Tools

```bash
docker --version
kubectl version --client
go version
git --version
```

> **Note:** Minikube, k6, and Hurl must be installed manually in Cloud Shell — see the steps below.

### Install k6 on Cloud Shell

```bash
sudo gpg -k
sudo gpg --no-default-keyring --keyring /usr/share/keyrings/k6-archive-keyring.gpg \
  --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69
echo "deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] https://dl.k6.io/deb stable main" \
  | sudo tee /etc/apt/sources.list.d/k6.list
sudo apt-get update && sudo apt-get install k6
k6 version
```

### Install Hurl on Cloud Shell

```bash
HURL_VERSION=$(curl -s https://api.github.com/repos/Orange-OpenSource/hurl/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
curl -LO "https://github.com/Orange-OpenSource/hurl/releases/download/${HURL_VERSION}/hurl_${HURL_VERSION}_amd64.deb"
sudo dpkg -i "hurl_${HURL_VERSION}_amd64.deb"
hurl --version
```

---

## Pre-requisites

| Tool | Install |
| ---- | ------- |
| Docker | [docs.docker.com/get-docker](https://docs.docker.com/get-docker/) |
| Minikube | `curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64 && sudo install minikube-linux-amd64 /usr/local/bin/minikube` |
| kubectl | `curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && sudo install kubectl /usr/local/bin/kubectl` |
| Go 1.22+ | `sudo apt install golang-go` or [go.dev/dl](https://go.dev/dl/) |
| k6 | `sudo apt install k6` or [k6.io/docs/get-started/installation](https://k6.io/docs/get-started/installation/) |
| Hurl | `HURL_VERSION=$(curl -s https://api.github.com/repos/Orange-OpenSource/hurl/releases/latest \| grep '"tag_name"' \| cut -d'"' -f4) && curl -LO "https://github.com/Orange-OpenSource/hurl/releases/download/${HURL_VERSION}/hurl_${HURL_VERSION}_amd64.deb" && sudo dpkg -i "hurl_${HURL_VERSION}_amd64.deb"` |

---

## Phase 1 – Environment Setup (15–20 min)

### 1.1 Fork Template Repo

1. Open [https://github.com/pradist/deployment](https://github.com/pradist/deployment)
2. Click **Fork** (top-right) → **Create fork**
3. Clone your own fork:

```bash
# Set your GitHub username (use this for all subsequent commands)
export GITHUB_USERNAME=<your-github-username>

git clone https://github.com/${GITHUB_USERNAME}/deployment.git
cd deployment
```

### 1.2 Start Minikube

```bash
minikube start --driver=docker
minikube status
```

Expected output: `Done! kubectl is now configured to use "minikube" cluster`

### 1.3 Verify Node

```bash
kubectl get nodes
# NAME       STATUS   ROLES           AGE   VERSION
# minikube   Ready    control-plane   30s   v1.xx.x
```

### 1.4 Open Kubernetes Dashboard

```bash
minikube addons enable dashboard

# Wait until the Dashboard Pod is ready before port-forwarding
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=kubernetes-dashboard -n kubernetes-dashboard --timeout=40s

kubectl port-forward -n kubernetes-dashboard service/kubernetes-dashboard 8080:80
# Click Web Preview → Preview on Port 8080
```

---

## Phase 2 – Database & Networking (20 min)

> Open a new tab and navigate into the project folder first:
>
> ```bash
> cd ~/deployment
> ```

### 2.1 Deploy PostgreSQL

```bash
kubectl apply -f k8s/postgres-db.yaml
```

### 2.2 Verify Pods and Services

```bash
kubectl get pods -w          # Wait until status is Running
kubectl get svc db-service   # Confirm ClusterIP and port 5432
```

> **Key concept:** The app connects to `db-service` by name, not by IP address.  
> Kubernetes DNS automatically resolves the Service name to its ClusterIP.  
> The IP may change every time a Pod restarts, but the Service name always stays the same.

### 2.3 Test Database Connection

```bash
kubectl exec -it deploy/postgres -- psql -U postgres -d appdb -c "\dt"
```

> If you see the "items" table, the init script ran successfully

### 2.4 Connect with VS Code SQLTools (optional)

* Install both extensions in VS Code:
  | [SQLTools](https://marketplace.visualstudio.com/items?itemName=mtxr.sqltools)

* Port-forward the database to your local machine:

```bash
  kubectl port-forward svc/db-service 5432:5432 &
```

* In VS Code, open **SQLTools → Add New Connection** and fill in:

| Field | Value |
| ----- | ----- |
| Connection name | `appdb` |
| Server / Host | `localhost` |
| Port | `5432` |
| Database | `appdb` |
| Username | `postgres` |
| Password | `postgres` |

* Click **Test Connection** → **Save Connection** → run queries directly from the editor

---

## Phase 3 – The Reliable Go API (30 min)

### 3.1 Understand the Three Key Sections

Open `api/main.go` and review:

| Section | Function | Description |
| ------- | -------- | ----------- |
| **Health Probes** | `healthLive()`, `healthReady()` | `/livez` = container is alive, `/readyz` = ready to receive traffic |
| **Graceful Shutdown** | `signal.Notify(quit, syscall.SIGTERM)` | Catches SIGTERM from Kubernetes and drains connections before exiting |
| **Prometheus Metrics** | `prometheusMiddleware()` | Counts request totals and durations for every endpoint |

### 3.2 Build Docker Image

```bash
# Set your Docker Hub username (use this for all subsequent commands)
export DOCKER_USERNAME=<your-dockerhub-username>

cd api

# Download dependencies (generates go.sum)
go mod tidy

cd ..

# Build the image (multi-stage)
docker build -t ${DOCKER_USERNAME}/go-api:latest ./api

# Check image size (should be very small due to scratch base)
docker images | grep go-api
```

### 3.3 Test Locally Before Pushing

```bash
# Port-forward DB from minikube — bind to all interfaces so Docker can reach it
kubectl port-forward --address 0.0.0.0 svc/db-service 5432:5432 &

# Get the host IP
HOST_IP=$(hostname -I | awk '{print $1}')

# Run container with environment variables
docker run --rm -d -p 8081:8080 \
  -e DB_HOST=${HOST_IP} \
  -e DB_PORT=5432 \
  -e DB_USER=postgres \
  -e DB_PASSWORD=postgres \
  -e DB_NAME=appdb \
  ${DOCKER_USERNAME}/go-api:latest

# Test endpoints
curl http://localhost:8081/livez
curl http://localhost:8081/readyz
curl http://localhost:8081/
curl http://localhost:8081/items
```

### 3.4 Stop the container

```bash
docker stop $(docker ps -q --filter ancestor=${DOCKER_USERNAME}/go-api:latest)
```

### 3.5 Push Image to Docker Hub

```bash
docker login
docker push ${DOCKER_USERNAME}/go-api:latest
```

### 3.6 Update Image Name in k8s/api-deployment.yaml

```bash
sed -i "s/DOCKER_USERNAME/${DOCKER_USERNAME}/g" k8s/api-deployment.yaml
```

### 3.7 Deploy Go API

```bash
kubectl apply -f k8s/api-deployment.yaml
kubectl get pods -w   # Wait until status is Running
```

### 3.8 Test the API via Minikube

```bash
NODE_IP=$(minikube ip)
curl http://${NODE_IP}:30080/
curl http://${NODE_IP}:30080/livez
curl http://${NODE_IP}:30080/readyz
```

---

## Phase 4 – CI/CD Automation (40 min)

### 4.1 Configure GitHub Secrets

> **Must do this before running the pipeline** — without these secrets, the Docker login step will fail.

**Step 1 – Create a Docker Hub Access Token:**

1. Go to [https://hub.docker.com/settings/security](https://hub.docker.com/settings/security)
2. Click **New Access Token** → give it a name (e.g. `github-actions`) → **Generate**
3. Copy the token (it will only be shown once)

**Step 2 – Add secrets to your GitHub repo:**

1. Go to your forked repo on GitHub
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret** and add both:

| Secret Name | Value |
| ----------- | ----- |
| `DOCKER_USERNAME` | Your Docker Hub username |
| `DOCKER_TOKEN` | The access token you just created |

### 4.2 Install Self-hosted Runner on Cloud Shell

```bash
# Go to GitHub repo → Settings → Actions → Runners → New self-hosted runner
# Select OS: Linux, Architecture: x64, then follow the commands shown on screen

mkdir -p ~/actions-runner && cd ~/actions-runner
curl -o actions-runner-linux-x64-2.316.1.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.316.1/actions-runner-linux-x64-2.316.1.tar.gz
tar xzf ./actions-runner-linux-x64-2.316.1.tar.gz

# Get the registration token from GitHub:
# → Go to your repo → Settings → Actions → Runners → New self-hosted runner
# → Select Linux / x64 → Copy the token shown on that page (valid for 1 hour)
./config.sh --url https://github.com/${GITHUB_USERNAME}/deployment --token <TOKEN>

# Start runner in the background using tmux
tmux new -s runner
./run.sh
# Press Ctrl+B then D to detach
```

> **Note:** Cloud Shell has only **5GB** of home disk. If the pipeline fails with `ENOSPC: no space left on device`, run this to free up space before retrying:
>
> ```bash
> # Check disk usage
> df -h ~
> du -sh ~/* 2>/dev/null | sort -rh | head -10
>
> # Clear runner tool cache and build artifacts
> rm -rf ~/actions-runner/_work
>
> # Clear Docker cache
> docker system prune -af --volumes
>
> # Clear Go module/build cache
> go clean -cache -modcache
>
> # Remove leftover .deb files
> rm -f ~/*.deb
> ```

### 4.3 The Magic Moment – Test CI/CD

```bash
cd ~/deployment

# Edit the welcome message in api/main.go
# Line: "message": "Hello from Go API v1.0.0 🚀"
# Change to: "message": "Hello from Go API v2.0.0 ✨"

git add api/main.go
git commit -m "feat: update welcome message to v2.0.0"
git push origin main
```

Watch GitHub Actions — the pipeline will automatically run Build → Push → Deploy!

```bash
# Verify the Pod has been updated
kubectl rollout status deployment/go-api
curl http://$(minikube ip):30080/
```

---

## Phase 5 – Load Test & Monitoring (30 min)

### 5.1 Deploy Prometheus & Grafana

```bash
kubectl apply -f k8s/prometheus.yaml
kubectl apply -f k8s/grafana.yaml
kubectl get pods -w   # Wait until both Pods are Running
```

### 5.2 Access Grafana via Port-forward

```bash
kubectl port-forward svc/grafana-service 3000:3000 &
# Open http://localhost:3000
# Login: admin / admin123
```

**Configure a Dashboard:**

1. **Connections → Data Sources** → Verify Prometheus URL = `http://prometheus-service:9090`
2. **Dashboards → New → Import** → Enter ID `12708` (Go Metrics Dashboard) or `1860` (Node Exporter)
3. Add custom panels:
   * Query: `rate(http_requests_total[1m])` → Requests per second
   * Query: `histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[1m]))` → P95 latency

### 5.3 Run k6 Load Test

```bash
# Open a new terminal
k6 run -e BASE_URL=http://$(minikube ip):30080 tests/k6/script.js
```

### 5.4 Observe Grafana

Watch the graphs in Grafana while k6 is running:

* **Request rate** will spike
* **CPU usage** of Pods will increase
* **P95 latency** will change with load

### 5.5 Functional Test with Hurl

```bash
hurl --variable base_url=http://$(minikube ip):30080 \
  tests/hurl/api.hurl --verbose
```

---

## Phase 6 – Scaling & Troubleshooting (20 min)

### 6.1 Manual Scaling

When you see CPU spike in Grafana:

```bash
kubectl scale deployment go-api --replicas=5
kubectl get pods -w   # Watch new Pods being created
```

### 6.2 Verify Load Distribution in Grafana

Add a panel in Grafana with the query:

```promql
rate(http_requests_total[30s])
```

You will see each Pod (by `pod` label) handling a separate share of traffic.

### 6.3 Log Analysis

```bash
# Stream logs in real-time during k6 test
kubectl logs -f deployment/go-api

# Stream logs for a specific Pod
kubectl logs -f <pod-name>

# Stream logs across multiple Pods simultaneously (requires stern)
stern go-api
```

### 6.4 Scale Down

```bash
kubectl scale deployment go-api --replicas=2
```

---

## What You Learned

| Topic | What was done |
| ----- | ------------- |
| **Reliability** | Health probes (`/livez`, `/readyz`) + Graceful shutdown |
| **Observability** | Prometheus metrics + Grafana dashboard |
| **Automation** | GitHub Actions + Self-hosted Runner |
| **Scalability** | Manual scaling + HPA (auto-scale) |
| **Testing** | Load test (k6) + Functional test (Hurl) |

---

## Stuck?

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common errors and quick fixes.
