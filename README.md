<div align="center">

# 🚀 zero-to-prod-k8s

### Containerised Uptime Stack on Kubernetes with Local CI/CD

*A production-grade DevOps project running entirely offline — no cloud required.*

[![Made with Docker](https://img.shields.io/badge/Made%20with-Docker-2496ED?style=flat-square&logo=docker&logoColor=white)](https://docker.com)
[![Kubernetes](https://img.shields.io/badge/Orchestration-Kubernetes-326CE5?style=flat-square&logo=kubernetes&logoColor=white)](https://kubernetes.io)
[![kind](https://img.shields.io/badge/Cluster-kind-F5A800?style=flat-square&logo=kubernetes&logoColor=white)](https://kind.sigs.k8s.io)
[![Jenkins](https://img.shields.io/badge/CI%2FCD-Jenkins-D24939?style=flat-square&logo=jenkins&logoColor=white)](https://jenkins.io)
[![Python](https://img.shields.io/badge/App-Python%203.12-3776AB?style=flat-square&logo=python&logoColor=white)](https://python.org)
[![PostgreSQL](https://img.shields.io/badge/Database-PostgreSQL%2016-336791?style=flat-square&logo=postgresql&logoColor=white)](https://postgresql.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg?style=flat-square)](LICENSE)

<br/>

[Quick Start](#-quick-start) · [Architecture](#-architecture) · [Project Structure](#-project-structure) · [Sprints](#-sprints) · [Prerequisites](#-prerequisites)

</div>

---

## 📖 Overview

This project transforms a basic uptime monitoring concept into a fully containerised, Kubernetes-native stack with a local CI/CD pipeline — all running on your own machine with no cloud account needed.

**What gets built:**

- A **Flask API** (`/health`, `/echo`) containerised with multi-stage Docker builds, running as non-root
- An **Nginx edge proxy** with custom access logs tracking `$request_time`
- A **PostgreSQL StatefulSet** with primary + replica streaming replication
- **Three CronJobs** — metrics writer, log parser, SLO alert checker
- A **kind cluster** (2 nodes) with Ingress-Nginx, cert-manager TLS, HPA, RBAC, and NetworkPolicies
- A **Jenkins pipeline** (in Docker) that lints → tests → builds → scans → pushes → deploys → smoke tests → auto-rollbacks on failure
- **Kyverno policy gates** denying pods without non-root context or resource limits
- A **blue/green deployment** script for zero-downtime rollouts

---

## ⚡ Quick Start

```bash
# 1. Clone
git clone https://github.com/<YOUR_USERNAME>/zero-to-prod-k8s.git
cd zero-to-prod-k8s

# 2. Copy and fill in secrets
cp .env.example .env
# Edit .env — set a strong POSTGRES_PASSWORD

# 3. Spin up the full stack (cluster + registry + deploy)
make all

# 4. Test it
curl -k https://uptime.local/health
# → {"status":"ok","version":"..."}
```

> **First run takes ~5 minutes** — kind downloads images, cert-manager spins up, pods become ready.

---

## 🏗 Architecture

```
                        ┌─────────────────────────────────────────────┐
                        │           kind cluster (uptime-dev)          │
                        │                                              │
  Browser / curl        │  ┌──────────────┐     ┌──────────────────┐  │
       │                │  │  ingress-    │     │   cert-manager   │  │
       │  HTTPS         │  │  nginx       │     │  (SelfSigned TLS)│  │
       └───────────────►│  │  :443        │     └──────────────────┘  │
                        │  └──────┬───────┘                           │
                        │         │ /app/*                            │
                        │  ┌──────▼───────┐     ┌──────────────────┐  │
                        │  │  Flask App   │────►│   PostgreSQL     │  │
                        │  │  (HPA 1-3)   │     │   StatefulSet    │  │
                        │  └──────────────┘     │  primary+replica │  │
                        │                       └──────────────────┘  │
                        │  CronJobs:  metrics-job  log-parser  alerts  │
                        └─────────────────────────────────────────────┘
                                          ▲
                        ┌─────────────────┴───────────────────────────┐
                        │         Jenkins CI/CD (Docker)               │
                        │  lint→test→build→scan→push→deploy→smoke      │
                        │              localhost:8090                   │
                        └─────────────────────────────────────────────┘
                                          ▲
                        ┌─────────────────┴───────────────────────────┐
                        │       Local Registry  (localhost:5001)       │
                        └─────────────────────────────────────────────┘
```

### Components

| Component | Technology | Purpose |
|---|---|---|
| **edge** | Nginx 1.27-alpine | Reverse proxy, TLS termination, access logs |
| **app** | Flask + Gunicorn | REST API — `/health`, `/echo` |
| **db** | PostgreSQL 16 | Primary + streaming replica, PVC-backed |
| **metrics-job** | Python 3.12 CronJob | Polls `/health`, writes to Postgres every 5 min |
| **log-parser** | Python 3.12 CronJob | Parses Nginx logs → daily CSV (00:00 UTC) |
| **alerts** | Alpine bash CronJob | Checks SLO breach, POSTs to webhook (every 15 min) |
| **registry** | registry:2 | Local container registry on port 5001 |
| **ci** | Jenkins LTS | Pipeline-as-code, auto-rollback on failure |

---

## 📁 Project Structure

```
zero-to-prod-k8s/
├── app/                        # Flask application
│   ├── Dockerfile              # Multi-stage: builder (tests) → slim runtime
│   └── src/
│       ├── main.py             # Flask routes + SIGTERM handler
│       ├── test_main.py        # Pytest unit tests (run inside Docker build)
│       ├── requirements.txt    # flask, gunicorn
│       └── requirements-dev.txt# pytest, pytest-cov
│
├── edge/                       # Nginx edge proxy
│   ├── Dockerfile
│   └── nginx.conf              # Custom log format with $request_time
│
├── jobs/
│   ├── metrics/                # Healthcheck → Postgres CronJob
│   │   ├── Dockerfile
│   │   ├── healthcheck.py
│   │   └── requirements.txt
│   ├── log-parser/             # Nginx log → CSV CronJob
│   │   ├── Dockerfile
│   │   └── parse.py
│   └── alerts/                 # SLO breach alerter CronJob
│       ├── Dockerfile
│       └── alert.sh
│
├── k8s/
│   ├── base/                   # Kustomize base manifests
│   │   ├── namespace.yaml
│   │   ├── app/                # Deployment, Service, HPA, PDB
│   │   ├── edge/               # Deployment, Service, Ingress
│   │   ├── db/                 # StatefulSet, Services (headless + ClusterIP)
│   │   ├── jobs/               # CronJobs (metrics, log-parser, alerts)
│   │   ├── rbac/               # ServiceAccounts, Roles, RoleBindings
│   │   ├── netpol/             # NetworkPolicies (default-deny + allow rules)
│   │   └── issuer/             # cert-manager SelfSigned ClusterIssuer
│   └── overlays/
│       └── dev/                # Dev overlay (image tags, replica counts)
│
├── ci/
│   ├── Jenkinsfile             # 8-stage pipeline-as-code
│   └── docker-compose.ci.yml  # Jenkins + Docker socket mount
│
├── registry/
│   └── compose.yml            # Local registry:2 on port 5001
│
├── scripts/
│   ├── kind-up.sh             # Create cluster + install addons
│   ├── connect-registry.sh    # Wire registry to kind network
│   ├── load-secrets.sh        # Create K8s Secrets from .env
│   ├── rollout.sh             # Blue/green deployment cutover
│   └── smoke.sh               # Curl health check + latency assert
│
├── policies/
│   └── kyverno/
│       └── require-nonroot-limits.yaml  # Deny root pods + missing limits
│
├── docs/
│   ├── architecture.md
│   ├── runbook.md             # Resilience drills + recovery procedures
│   └── troubleshooting.md
│
├── docker-compose.yml         # Local dev stack (edge + app + db)
├── Makefile                   # Top-level task runner
├── .env.example               # Copy to .env and fill in secrets
├── .hadolint.yaml             # Dockerfile linter config
├── .kube-linter-config.yaml   # K8s manifest linter config
└── .trivyignore               # CVE suppression list
```

---

## ✅ Prerequisites

Install these tools before starting:

| Tool | Version | Install |
|---|---|---|
| Docker Desktop | 24+ | [docs.docker.com](https://docs.docker.com/get-docker/) |
| kubectl | 1.30+ | [kubernetes.io](https://kubernetes.io/docs/tasks/tools/) |
| kind | 0.23+ | `brew install kind` |
| kustomize | 5+ | `brew install kustomize` |
| git | any | [git-scm.com](https://git-scm.com/downloads) |
| make | any | Pre-installed on Linux/Mac |
| hey *(load tester)* | any | `go install github.com/rakyll/hey@latest` |

Verify all tools:
```bash
docker --version && kubectl version --client && kind version && kustomize version
```

---

## 🔐 Environment Setup

```bash
# Copy the example file
cp .env.example .env
```

Edit `.env` with your values:

```env
POSTGRES_USER=uptime
POSTGRES_PASSWORD=YourStrongPassword123!   # ← change this
POSTGRES_DB=uptimedb
WEBHOOK_URL=http://localhost:9000/hooks/alert
SLO_THRESHOLD=99
APP_PORT=5000
```

> ⚠️ **Never commit `.env`** — it's in `.gitignore`. The `postgres:16-alpine` image reads these on first boot and auto-creates the user and database. See [How Postgres Setup Works](#how-postgres-setup-works) below.

---

## 🎯 Sprints

This project is structured as a 2-week, 4-sprint plan.

### Sprint 1 — Docker Depth

**Goal:** Solid container builds, minimal images, non-root, healthchecks.

```bash
# Local dev (no Kubernetes needed)
docker compose up --build -d
curl http://localhost:8080/app/health

# Lint Dockerfiles
make lint

# Scan for CVEs (must be 0 CRITICAL)
make scan
```

**Acceptance criteria:**
- `docker images` shows app runtime < 150 MB
- `trivy` reports 0 CRITICAL CVEs
- `curl http://localhost:8080/app/health` returns `{"status":"ok"}`

---

### Sprint 2 — Kubernetes Fundamentals

**Goal:** Cluster up, TLS Ingress, StatefulSet DB, probes, HPA, RBAC, NetworkPolicies.

```bash
# Create cluster + registry
make cluster

# Build, push, and deploy
make deploy

# Add uptime.local to /etc/hosts
echo "127.0.0.1 uptime.local" | sudo tee -a /etc/hosts

# Test TLS
curl -k https://uptime.local/health

# Verify Postgres replica
kubectl exec -it postgres-1 -n uptime-dev -- \
  psql -U uptime -c "SELECT pg_is_in_recovery();"
# → t  (replica is in recovery mode ✓)

# Load test — watch HPA scale
hey -n 50000 -c 100 http://uptime.local/health &
kubectl get hpa -n uptime-dev -w
```

**Acceptance criteria:**
- `kubectl get pods -n uptime-dev` → all `Running`
- `kubectl describe ingress -n uptime-dev` shows TLS
- `kubectl top pods` works; HPA scales 1 → 3 under load
- Postgres replica reports `pg_is_in_recovery() = t`

---

### Sprint 3 — Local CI/CD

**Goal:** Pipeline builds, scans, pushes to local registry, deploys to K8s.

```bash
# Start Jenkins
make ci
# Open http://localhost:8090 → paste initial admin password → setup

# Get initial password
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```

**Pipeline stages:**

```
lint → test → build → scan → push → deploy → smoke → [rollback on failure]
```

**Acceptance criteria:**
- Commit → Jenkins builds + deploys new tag
- `kubectl rollout history deployment/app -n uptime-dev` shows multiple revisions
- Bad image tag → rollback stage fires automatically

---

### Sprint 4 — Reliability & Policy 

**Goal:** PDB prevents outage during drain, Kyverno gate blocks bad manifests, blue/green with zero downtime.

```bash
# Apply PodDisruptionBudgets + Kyverno
kubectl apply -f k8s/base/app/pdb.yaml
kubectl apply -f https://github.com/kyverno/kyverno/releases/download/v1.12.0/install.yaml
kubectl apply -f policies/kyverno/require-nonroot-limits.yaml

# Test Kyverno gate (should be denied)
kubectl run bad-pod --image=nginx -n uptime-dev --dry-run=server

# Blue/green deploy
bash scripts/rollout.sh <git-sha>
```

**Acceptance criteria:**
- `kubectl drain` is blocked by PDB on the last pod
- `kubectl run bad-pod --image=nginx` is denied by Kyverno
- Blue/green cutover with no downtime (verify via continuous curl)

---

## 🛠 Makefile Reference

```bash
make all        # Full end-to-end: cluster + build + push + deploy + smoke
make cluster    # Create kind cluster, start registry, install addons
make build      # Build all 5 Docker images
make push       # Build + push to localhost:5001
make deploy     # Load secrets + push + apply kustomize overlay
make smoke      # Run curl smoke tests against https://uptime.local/health
make lint       # hadolint (Dockerfiles) + kube-linter (manifests)
make test       # Run pytest inside Docker builder stage
make scan       # Trivy CVE scan on app image
make ci         # Extract kubeconfig + start Jenkins compose stack
make dev-up     # docker compose up (local dev, no K8s)
make dev-down   # docker compose down
make down       # Destroy cluster + registry + Jenkins
make clean      # Remove local images from localhost:5001
```

---

## 🔒 Security Highlights

| Concern | Mitigation |
|---|---|
| Container privileges | All containers run as UID 10001 (`runAsNonRoot: true`) |
| Image vulnerabilities | Trivy scans every build — pipeline fails on HIGH/CRITICAL |
| Dockerfile quality | hadolint lints every Dockerfile in CI |
| K8s manifest quality | kube-linter checks all manifests in CI |
| Network segmentation | Default-deny NetworkPolicy; only explicitly allowed traffic flows |
| RBAC | Dedicated ServiceAccounts with least-privilege roles |
| Secret management | K8s Secrets from `.env` via `load-secrets.sh` — never committed to git |
| Policy gate | Kyverno `Enforce` mode blocks non-root or resource-limitless pods |

---

## 🗄 How Postgres Setup Works

Postgres is **not manually installed** — Docker handles it automatically.

When `postgres:16-alpine` starts on an **empty volume** for the first time, it reads the three environment variables and bootstraps itself:

```
POSTGRES_USER     → CREATE USER uptime ...
POSTGRES_PASSWORD → ALTER USER uptime PASSWORD '...'
POSTGRES_DB       → CREATE DATABASE uptimedb OWNER uptime
```

**In dev (docker compose):** These come from your `.env` file.

**In Kubernetes (Sprint 2+):** These come from the `db-secret` K8s Secret, created by `scripts/load-secrets.sh`.

```bash
# Connect to Postgres (dev)
docker compose exec db psql -U uptime -d uptimedb

# Connect to Postgres (Kubernetes)
kubectl exec -it postgres-0 -n uptime-dev -- psql -U uptime -d uptimedb
```

> **Note:** If you change `POSTGRES_PASSWORD` after the data volume already exists, it won't take effect automatically. Either `docker compose down -v` to wipe and restart, or run `ALTER USER uptime PASSWORD 'new'` inside psql.

---

## 🔥 Resilience Drills

Documented in [`docs/runbook.md`](docs/runbook.md). Summary:

```bash
# Drill 1: Kill primary DB → replica stays read-only, primary recovers
kubectl delete pod postgres-0 -n uptime-dev

# Drill 2: PDB prevents full app outage during node drain
kubectl drain <worker-node> --ignore-daemonsets --delete-emptydir-data

# Drill 3: HPA load test
hey -n 100000 -c 200 http://uptime.local/health &
kubectl get hpa -n uptime-dev -w

# Drill 4: Bad image → pipeline auto-rollback
kubectl set image deployment/app app=localhost:5001/uptime/app:broken -n uptime-dev
kubectl rollout history deployment/app -n uptime-dev
```

---

## 🐛 Troubleshooting

**Pods stuck in `ImagePullBackOff`**
```bash
# Check registry is connected to kind
bash scripts/connect-registry.sh
# Verify image exists in registry
curl http://localhost:5001/v2/uptime/app/tags/list
```

**cert-manager Certificate not Ready**
```bash
kubectl describe certificate uptime-tls -n uptime-dev
kubectl get challenges -n uptime-dev
# SelfSigned issuer should resolve immediately — if stuck, delete and re-apply
kubectl delete certificate uptime-tls -n uptime-dev
kubectl apply -f k8s/base/issuer/selfsigned.yaml
```

**HPA shows `<unknown>` for CPU**
```bash
# metrics-server needs --kubelet-insecure-tls for kind
kubectl patch deployment metrics-server -n kube-system --type=json \
  -p '[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

**Postgres replica not syncing**
```bash
# Check initContainer logs
kubectl logs postgres-1 -n uptime-dev -c init-replica
# Verify primary is accepting connections
kubectl exec postgres-0 -n uptime-dev -- pg_isready -U uptime
```

**Jenkins can't reach cluster**
```bash
# Regenerate kubeconfig with Docker host IP
kind get kubeconfig --name uptime-dev > kubeconfig-ci
sed -i.bak 's/127.0.0.1/host.docker.internal/g' kubeconfig-ci
```

Full troubleshooting guide: [`docs/troubleshooting.md`](docs/troubleshooting.md)

---

## 📚 Key Concepts Practised

- **Multi-stage Docker builds** — separate builder and runtime stages; tests run inside the build
- **Non-root containers** — UID 10001 in all images; `runAsNonRoot: true` in pod specs
- **Kubernetes probes** — readiness vs liveness; `preStop` hooks for graceful drain
- **StatefulSets** — headless Services, stable DNS names, `initContainers` for replica bootstrap
- **Kustomize** — base + overlay pattern; `kustomize edit set image` in CI
- **HPA** — CPU-based autoscaling with `stabilizationWindowSeconds` to prevent thrashing
- **RBAC** — least-privilege ServiceAccounts; `automountServiceAccountToken: false`
- **NetworkPolicies** — default-deny namespace; explicit allow rules per flow
- **PodDisruptionBudgets** — `minAvailable: 1` to survive voluntary disruptions
- **Blue/green deployments** — slot-based label switching; rollback without downtime
- **Pipeline-as-code** — `Jenkinsfile` with parallel stages and `post { failure }` rollback hook

---

## 👤 Author

**Devesh Raj**

---

<div align="center">

*Built entirely offline · No cloud account required · Runs on your laptop*

</div>
