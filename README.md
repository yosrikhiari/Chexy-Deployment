# Chexy — Deployment

Kubernetes manifests and a Jenkins pipeline that build and deploy the whole **Chexy** stack.
One of four repositories:

| Repo | Role |
|---|---|
| [Chexy-B](https://github.com/yosrikhiari/Chexy-B) | Spring Boot API, realtime, Keycloak auth, MongoDB, Kafka |
| [Chexy-F](https://github.com/yosrikhiari/Chexy-F) | React 18 + Vite client |
| [Chexy-M](https://github.com/yosrikhiari/Chexy-M) | Flask AI service (Stockfish bots, opening detection, RPG enemy armies) |
| **Chexy-Deployment** (this one) | Kubernetes + Jenkins |

## What is deployed

`kubernetes/deployment.yaml` is a single manifest with, in the `chexy` namespace:

| Kind | What |
|---|---|
| `Namespace` | `chexy` |
| `ConfigMap` / `Secret` | `chexy-config`, `chexy-secrets` (Keycloak admin and DB passwords, mail password, Hugging Face token — all via `secretKeyRef`, nothing literal), the Keycloak realm export, a Postgres init script |
| `PersistentVolume` / claims | `local-storage` host paths for PostgreSQL (`/data/postgres`) and MongoDB (`/data/mongodb`) |
| `Deployment` + `Service` | `postgres:16.2` (Keycloak's DB), `mongo:7.0`, `quay.io/keycloak/keycloak:26.1.4`, `yosrikhiari/chexy-backend`, `yosrikhiari/chexy-frontend`, `yosrikhiari/chexy-ai-model` — with `/health` readiness and liveness probes on the app services |
| `Ingress` | routes the frontend and API |

## The pipeline

`Jenkinsfile` stages: **Clone Repositories** (the three app repos) → **Verify Dockerfiles** →
**Build and Push Images** (`docker.build` tagged with the Jenkins build number, pushed to
Docker Hub with stored credentials) → **Test Kubernetes Connection** → **Create ConfigMap** →
**Deploy to Kubernetes** (`kubectl apply` with a kubeconfig credential).

`JenkinsContainerFixer.sh` writes an adjusted kubeconfig inside the Jenkins container so
`kubectl` from Jenkins can reach the cluster — the workaround for running Jenkins itself in
Docker next to the cluster.

## Run

```bash
# apply everything
kubectl apply -f kubernetes/deployment.yaml
kubectl -n chexy get pods

# or let Jenkins do it: create a pipeline job pointing at this repo's Jenkinsfile,
# add the docker-hub, github and kubeconfig credentials referenced at the top of the file
```

Built as a side project (2025). Images: `yosrikhiari/chexy-backend`, `yosrikhiari/chexy-frontend`,
`yosrikhiari/chexy-ai-model` on Docker Hub.
