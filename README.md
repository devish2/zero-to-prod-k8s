<div align="center">

# Zero-To-Prod-K8S

**Containerised Uptime Stack on Kubernetes with Local CI/CD**

*Production-grade DevOps project — fully offline, no cloud required.*

[![Docker](https://img.shields.io/badge/Docker-24+-2496ED?style=flat-square&logo=docker&logoColor=white)](https://docker.com)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-kind-326CE5?style=flat-square&logo=kubernetes&logoColor=white)](https://kind.sigs.k8s.io)
[![Python](https://img.shields.io/badge/Python-3.12-3776AB?style=flat-square&logo=python&logoColor=white)](https://python.org)
[![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16-336791?style=flat-square&logo=postgresql&logoColor=white)](https://postgresql.org)
[![Jenkins](https://img.shields.io/badge/CI%2FCD-Jenkins-D24939?style=flat-square&logo=jenkins&logoColor=white)](https://jenkins.io)
[![Kyverno](https://img.shields.io/badge/Policy-Kyverno-1A6BAD?style=flat-square)](https://kyverno.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-22c55e?style=flat-square)](LICENSE)

<br/>

[Overview](#overview) · [Architecture](#architecture) · [Prerequisites](#prerequisites) · [Setup](#setup) · [Sprints](#sprints) · [Common Errors & Fixes](#common-errors--fixes) · [Makefile Reference](#makefile-reference)

</div>

---

## Overview

This project builds a fully containerised uptime monitoring stack on a local Kubernetes cluster with a working CI/CD pipeline — all running on your laptop with no cloud account.

**What gets built across 4 sprints:**

- **Flask API** — `/health` and `/echo` endpoints, multi-stage Docker build, non-root UID 10001, graceful SIGTERM shutdown
- **Nginx edge proxy** — custom access logs with `$request_time`, proxies to Flask
- **PostgreSQL StatefulSet** — primary + streaming replica, PVC-backed storage, auto-bootstrapped via env vars
- **Three CronJobs** — metrics writer (every 5 min), Nginx log parser (daily), SLO alert checker (every 15 min)
- **kind cluster** — 2 nodes, ingress-nginx, cert-manager TLS, HPA (1→3 replicas), RBAC, NetworkPolicies
- **Jenkins pipeline** — 8 stages: lint → test → build → scan → push → deploy → smoke → auto-rollback
- **Kyverno policy gate** — blocks pods missing non-root context or resource limits at admission
- **Blue/green deployment** — slot-based zero-downtime rollout script

---

## Architecture

```
  Browser / curl
       │ HTTPS
       ▼
  ┌─────────────────────────────────────────────────┐
  │          kind cluster  (uptime-dev ns)           │
  │                                                  │
  │  ingress-nginx ──► Flask App (HPA: 1-3 pods)    │
  │  cert-manager TLS        │                       │
  │                          ▼                       │
  │                   PostgreSQL StatefulSet         │
  │                   postgres-0 (primary)           │
  │                   postgres-1 (replica)           │
  │                                                  │
  │  CronJobs:  metrics-job  log-parser  alerts      │
  │  RBAC:      app-sa  db-sa  jobs-sa               │
  │  NetPol:    default-deny + explicit allow rules  │
  │  PDB:       minAvailable: 1  (app + db)          │
  │  Kyverno:   enforce non-root + resource limits   │
  └─────────────────────────────────────────────────┘
            ▲
  ┌─────────┴───────────────────────────────────────┐
  │   Jenkins  (Docker, localhost:8090)              │
  │   lint→test→build→scan→push→deploy→smoke         │
  │   auto-rollback on pipeline failure              │
  └─────────────────────────────────────────────────┘
            ▲
  ┌─────────┴───────────────────────────────────────┐
  │   Local Registry  (localhost:5001)               │
  │   Images: localhost:5001/uptime/<name>:tag       │
  └─────────────────────────────────────────────────┘
```

---

## Project Structure

```
zero-to-prod-k8s/
├── app/                          # Flask application
│   ├── Dockerfile                # Multi-stage: builder (runs pytest) → slim runtime
│   └── src/
│       ├── main.py               # /health, /echo routes + SIGTERM handler
│       ├── test_main.py          # Pytest tests (run inside Docker build stage)
│       ├── requirements.txt      # flask==3.0.3, gunicorn==22.0.0
│       └── requirements-dev.txt  # pytest==8.2.2, pytest-cov==5.0.0
│
├── edge/                         # Nginx reverse proxy
│   ├── Dockerfile
│   └── nginx.conf                # Custom log_format with $request_time
│
├── jobs/
│   ├── metrics/                  # Polls /health → writes to Postgres (every 5m)
│   │   ├── Dockerfile
│   │   ├── healthcheck.py
│   │   └── requirements.txt
│   ├── log-parser/               # Parses Nginx access.log → daily CSV
│   │   ├── Dockerfile
│   │   └── parse.py
│   └── alerts/                   # SLO breach → webhook (every 15m)
│       ├── Dockerfile
│       └── alert.sh
│
├── k8s/
│   ├── base/                     # Kustomize base
│   │   ├── namespace.yaml
│   │   ├── kustomization.yaml
│   │   ├── app/                  # deployment.yaml, service.yaml, hpa.yaml, pdb.yaml
│   │   ├── edge/                 # deployment.yaml, service.yaml, ingress.yaml
│   │   ├── db/                   # statefulset.yaml, service.yaml
│   │   ├── jobs/                 # cronjobs.yaml (all 3 jobs)
│   │   ├── rbac/                 # rbac.yaml — SAs, Role, RoleBinding
│   │   ├── netpol/               # networkpolicies.yaml
│   │   └── issuer/               # selfsigned.yaml — ClusterIssuer + Certificate
│   └── overlays/
│       └── dev/                  # kustomization.yaml — image tag overrides
│
├── ci/
│   ├── Jenkinsfile               # 8-stage pipeline with auto-rollback
│   └── docker-compose.ci.yml     # Jenkins + docker.sock mount
│
├── registry/
│   └── compose.yml               # registry:2 on localhost:5001
│
├── scripts/
│   ├── kind-up.sh                # Create 2-node cluster + install addons
│   ├── connect-registry.sh       # Wire registry container to kind network
│   ├── load-secrets.sh           # Create K8s Secrets from .env (idempotent)
│   ├── rollout.sh                # Blue/green slot-based cutover
│   └── smoke.sh                  # curl health + latency assert
│
├── policies/
│   └── kyverno/
│       └── require-nonroot-limits.yaml   # Enforce: deny root + no-limits pods
│
├── docs/
│   ├── architecture.md
│   ├── runbook.md
│   └── troubleshooting.md
│
├── docker-compose.yml            # Local dev (no K8s needed)
├── Makefile                      # Task runner
├── .env.example                  # Copy → .env, never commit .env
├── .hadolint.yaml                # Dockerfile linter config
├── .kube-linter-config.yaml      # K8s manifest linter config
└── .trivyignore                  # CVE suppression list
```

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Docker Desktop | 24+ | [docs.docker.com/get-docker](https://docs.docker.com/get-docker/) |
| kubectl | 1.30+ | [kubernetes.io/docs/tasks/tools](https://kubernetes.io/docs/tasks/tools/) |
| kind | 0.23+ | `brew install kind` |
| kustomize | 5+ | `brew install kustomize` |
| git | any | [git-scm.com](https://git-scm.com/downloads) |
| make | any | Pre-installed on Linux/Mac |
| hey | any | `go install github.com/rakyll/hey@latest` |

> **macOS users:** Disable **AirPlay Receiver** before starting — it occupies port 5000 which conflicts with the Flask container.
> **System Settings → General → AirDrop & Handoff → AirPlay Receiver → OFF**

Verify all tools:
```bash
docker --version && kubectl version --client && kind version && kustomize version
```

---

## Setup

### 1. Clone the repo

```bash
git clone https://github.com/devish2/zero-to-prod-k8s.git
cd zero-to-prod-k8s
```

### 2. Configure environment

```bash
cp .env.example .env
```

Edit `.env`:

```env
POSTGRES_USER=uptime
POSTGRES_PASSWORD=YourStrongPassword123!    # ← change this
POSTGRES_DB=uptimedb
WEBHOOK_URL=http://localhost:9000/hooks/alert
SLO_THRESHOLD=99
APP_PORT=5000
```

> **How Postgres bootstraps itself:** `postgres:16-alpine` reads `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB` on first boot with an empty volume and auto-creates the user and database. No manual `psql` commands needed.
>
> In **docker compose** → values come from `.env`
> In **Kubernetes** → values come from the `db-secret` Secret (created by `load-secrets.sh`)

### 3. Local dev stack (Sprint 1 — no Kubernetes)

```bash
docker compose up --build -d

curl http://localhost:5000/health
# → {"status":"ok","version":"dev-compose"}

curl http://localhost:8888/app/health
# → {"status":"ok","version":"dev-compose"}
```

### 4. Full Kubernetes deploy (Sprint 2+)

> ⚠️ Always run in this exact order — secrets must exist before pods start.

```bash
kubectl apply -f k8s/base/namespace.yaml   # 1. namespace first
bash scripts/load-secrets.sh               # 2. secrets second
kubectl apply -k k8s/overlays/dev          # 3. everything else

# Add DNS entry for TLS ingress
echo "127.0.0.1 uptime.local" | sudo tee -a /etc/hosts

curl -k https://uptime.local/health
# → {"status":"ok"}
```

---

## Sprints

### Sprint 1 — Docker Depth *(Days 1–4)*

Multi-stage builds, non-root containers, healthchecks, dev compose stack.

```bash
docker compose up --build -d   # bring up edge + app + db
make lint                       # hadolint all Dockerfiles
make scan                       # Trivy CVE scan — must be 0 CRITICAL
make test                       # run pytest inside Docker builder stage
```

**Acceptance criteria:**
- App image < 150 MB
- `trivy` → 0 CRITICAL CVEs
- `curl http://localhost:8888/app/health` → `{"status":"ok"}`

---

### Sprint 2 — Kubernetes Fundamentals *(Days 5–8)*

kind cluster, TLS Ingress, StatefulSet with streaming replication, HPA, RBAC, NetworkPolicies.

```bash
make cluster                    # kind cluster + registry + addons
make push                       # build + push all images to localhost:5001
make deploy                     # load secrets + kustomize apply

# Verify Postgres replication
kubectl exec -it postgres-0 -n uptime-dev -c postgres -- \
  psql -U uptime -c 'SELECT pg_is_in_recovery();'
# → f  (primary)

kubectl exec -it postgres-1 -n uptime-dev -c postgres -- \
  psql -U uptime -c 'SELECT pg_is_in_recovery();'
# → t  (replica ✓)

# HPA load test
hey -n 50000 -c 100 http://uptime.local/health &
kubectl get hpa -n uptime-dev -w
```

**Acceptance criteria:**
- `kubectl get pods -n uptime-dev` → all `Running`
- `curl -k https://uptime.local/health` → `{"status":"ok"}`
- Postgres replica: `pg_is_in_recovery() = t`
- HPA scales 1 → 3 under load

---

### Sprint 3 — Local CI/CD *(Days 9–12)*

Jenkins in Docker, 8-stage pipeline-as-code, auto-rollback on failure.

```bash
make ci
# Get initial admin password
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
# Open http://localhost:8090 → paste password → Install suggested plugins
# New Item → Pipeline → SCM: Git → Script Path: ci/Jenkinsfile
```

**Pipeline stages:**
```
lint → test → build → scan → push → deploy → smoke → rollback (on failure)
```

**Acceptance criteria:**
- Commit → Jenkins builds + deploys new image tag
- `kubectl rollout history deployment/app -n uptime-dev` shows revisions
- Broken image → rollback stage fires automatically

---

### Sprint 4 — Reliability & Policy *(Days 13–14)*

PodDisruptionBudgets, Kyverno policy gate, blue/green deploy, resilience drills.

```bash
# Install Kyverno (--server-side required for large CRDs)
kubectl apply -f https://github.com/kyverno/kyverno/releases/download/v1.12.0/install.yaml \
  --server-side

kubectl apply -f policies/kyverno/require-nonroot-limits.yaml

# Test gate — must be denied ✓
kubectl run bad-pod --image=nginx -n uptime-dev --dry-run=server 2>&1
# → admission webhook "validate.kyverno.svc-fail" denied the request:
#   check-nonroot: Pod must run as non-root
#   check-limits:  All containers must have resource limits

# Blue/green deploy
bash scripts/rollout.sh $(git rev-parse --short HEAD)
```

**Acceptance criteria:**
- `kubectl drain` blocked by PDB on last pod
- `kubectl run bad-pod --image=nginx` denied by Kyverno ✅
- Blue/green cutover completes with zero dropped requests

---

## Common Errors & Fixes

Real errors encountered while building this project.

---

### `yaml: unmarshal errors: mapping key already defined`
**Cause:** Duplicate keys in `docker-compose.yml` — service names like `db`, `app`, `edge` appear more than once.
**Fix:** Each service must appear exactly once. Replace the file with a clean version.

---

### `curl localhost:8080/app/health` returns HTML "Authentication required"
**Cause:** Port 8080 is captured by Docker Desktop's built-in dashboard.
**Fix:** Change edge host port to `8888` in `docker-compose.yml`:
```yaml
edge:
  ports:
    - "8888:80"
```

---

### `Ports are not available: address already in use` on port 5000
**Cause:** macOS AirPlay Receiver holds port 5000 via the `ControlCe` process.
**Fix:** System Settings → General → AirDrop & Handoff → AirPlay Receiver → **OFF**

---

### `IndentationError: expected an indented block after function definition`
**Cause:** Terminal heredoc pasting corrupted indentation in `test_main.py`.
**Fix:** Verify syntax before building:
```bash
python3 -c "import ast; ast.parse(open('app/src/test_main.py').read()); print('✓ ok')"
```

---

### `path config error; no 'name' field in node` (Kustomize)
**Cause:** Inline YAML brace syntax breaks Kustomize's name-reference transformer.
**Fix:** Always use expanded block style in all manifests:
```yaml
# ❌ breaks Kustomize
metadata: { name: jobs-sa, namespace: uptime-dev }

# ✅ works correctly
metadata:
  name: jobs-sa
  namespace: uptime-dev
```

---

### `Deployment: unknown field "containers"` (BadRequest)
**Cause:** `containers`, `template`, `strategy` fields are at wrong nesting — placed directly under `spec` instead of `spec.template.spec`.
**Fix:** Correct structure:
```yaml
spec:
  template:
    spec:
      containers:     # ← must be here
        - name: app
```

---

### `secret "db-secret" not found` → `Init:CreateContainerConfigError`
**Cause:** `kubectl apply -k` was run before `load-secrets.sh`.
**Fix:** Always apply in this order:
```bash
kubectl apply -f k8s/base/namespace.yaml
bash scripts/load-secrets.sh               # ← secrets before pods
kubectl apply -k k8s/overlays/dev
```

---

### `ImagePullBackOff` on app pod
**Cause:** Image not pushed to local registry, or registry not connected to kind network.
**Fix:**
```bash
docker compose -f registry/compose.yml up -d
bash scripts/connect-registry.sh
docker build -t localhost:5001/uptime/app:latest ./app
docker push localhost:5001/uptime/app:latest
kubectl delete pod -l app=flask-app -n uptime-dev
```

---

### Kyverno install fails: `metadata.annotations: Too long: must have at most 262144 bytes`
**Cause:** Kyverno v1.12.0 CRDs exceed the annotation size limit for standard `kubectl apply`.
**Fix:** Use server-side apply:
```bash
kubectl apply -f https://github.com/kyverno/kyverno/releases/download/v1.12.0/install.yaml \
  --server-side
```

---

### `git push` rejected: `non-fast-forward`
**Cause:** Remote has commits (e.g. auto-generated README) that local branch doesn't have.
**Fix:**
```bash
git pull origin main --rebase
git push origin main
```

---

## Security Highlights

| Concern | Implementation |
|---|---|
| Non-root containers | All images: `USER 10001`, `runAsNonRoot: true` in pod spec |
| CVE scanning | Trivy on every build — pipeline fails on HIGH/CRITICAL |
| Dockerfile linting | hadolint in CI lint stage |
| Manifest linting | kube-linter in CI lint stage |
| Network segmentation | Default-deny NetworkPolicy + explicit allow rules per flow |
| Least-privilege RBAC | Dedicated ServiceAccounts, `automountServiceAccountToken: false` |
| Secret management | K8s Secrets from `.env` via `load-secrets.sh` — never in git |
| Admission policy | Kyverno `Enforce` — blocks root pods and pods without limits |
| Availability | PodDisruptionBudget `minAvailable: 1` on app and db |

---

## Makefile Reference

```bash
make all        # Full setup: cluster + build + push + deploy + smoke
make cluster    # Create kind cluster, start registry, install addons
make build      # Build all 5 Docker images
make push       # Build + push all images to localhost:5001
make deploy     # Load secrets + push + kustomize apply
make smoke      # Smoke test https://uptime.local/health
make lint       # hadolint (Dockerfiles) + kube-linter (manifests)
make test       # Run pytest inside Docker builder stage
make scan       # Trivy CVE scan on app image
make ci         # Export kubeconfig + start Jenkins stack
make dev-up     # docker compose up (local dev, no K8s)
make dev-down   # docker compose down
make down       # Delete cluster + stop registry + stop Jenkins
make clean      # Remove local images from localhost:5001
```

---

## Resilience Drills

Full procedures in [`docs/runbook.md`](docs/runbook.md).

```bash
# Drill 1 — Kill primary DB, verify replica stays read-only
kubectl delete pod postgres-0 -n uptime-dev
kubectl exec -it postgres-1 -n uptime-dev -c postgres -- \
  psql -U uptime -c 'SELECT pg_is_in_recovery();'
# Expected: t

# Drill 2 — PDB prevents full drain outage
kubectl scale deployment/app --replicas=2 -n uptime-dev
kubectl drain <worker-node> --ignore-daemonsets --delete-emptydir-data
# Expected: "Cannot evict pod — would violate PodDisruptionBudget"
kubectl uncordon <worker-node>

# Drill 3 — HPA scales under load
hey -n 100000 -c 200 http://uptime.local/health &
kubectl get hpa -n uptime-dev -w
# Expected: REPLICAS 1 → 3

# Drill 4 — Kyverno gate test
kubectl run bad-pod --image=nginx -n uptime-dev --dry-run=server 2>&1
# Expected: denied — check-nonroot + check-limits
```

---

## Connecting to Postgres

```bash
# Local dev (docker compose)
docker compose exec db psql -U uptime -d uptimedb

# Kubernetes — primary
kubectl exec -it postgres-0 -n uptime-dev -c postgres -- psql -U uptime -d uptimedb

# Kubernetes — replica
kubectl exec -it postgres-1 -n uptime-dev -c postgres -- psql -U uptime -d uptimedb

# Useful queries
SELECT current_user, current_database();
SELECT pg_is_in_recovery();             -- f on primary, t on replica
SELECT * FROM checks ORDER BY ts DESC LIMIT 10;
```

> If you change `POSTGRES_PASSWORD` after the data volume already exists, either run `docker compose down -v` to reinitialise, or change it manually inside psql: `ALTER USER uptime PASSWORD 'newpassword';`

---

## Author

**Devesh Raj** · [github.com/devish2](https://github.com/devish2)

---

<div align="center">
<sub>Runs entirely on your laptop &nbsp;·&nbsp; No cloud account &nbsp;·&nbsp; No paid services</sub>
</div>
