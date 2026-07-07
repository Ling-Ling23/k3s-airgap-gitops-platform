# Commands
kubectl rollout restart deployment actions-runner-controller-gha-rs-controller -n arc-systems
kubectl get pods -n arc-runners
kubectl get ephemeralrunnerset -n arc-runners
kubectl logs -n arc-systems deploy/actions-runner-controller-gha-rs-controller
or
kubectl logs -n arc-systems -l app.kubernetes.io/name=gha-rs-controller # same output


# GitHub Actions Runner Controller (ARC) — Air-Gapped Setup

ARC runs self-hosted GitHub Actions runners as Kubernetes pods on k3s.
Because the cluster has no internet access, Helm charts are pre-rendered and images are mirrored to JFrog.

---

## Architecture

```
GitHub Enterprise          k3s cluster
──────────────────         ──────────────────────────────────────────────
  Repo / Org          ←──  AutoscalingRunnerSet  (arc-runners ns)
  Actions workflow         │  └─ runner Pod per job
                           │
                      ←──  EphemeralRunnerSet listener
                           │
                           ARC controller  (arc-systems ns)
```

- **Controller** (`arc-systems` namespace): watches `AutoscalingRunnerSet` CRDs, manages the listener.
- **Runner Scale Set** (`arc-runners` namespace): scales runner pods 0 → N based on queued jobs.

---

## One-Time Setup (on an internet-connected machine)

### 1. Pull and render controller manifests

```bash
CHART_VERSION=0.9.3
JFROG=""

helm pull oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller \
  --version ${CHART_VERSION} --untar --untardir /tmp/arc-charts

helm template actions-runner-controller \
  /tmp/arc-charts/gha-runner-scale-set-controller \
  --namespace arc-systems \
  --set replicaCount=1 \
  --include-crds \
  > argocd/team1/charts/actions-runner-controller/manifests.yaml
```

### 2. Pull and render runner scale-set manifests

```bash
helm pull oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set \
  --version ${CHART_VERSION} --untar --untardir /tmp/arc-charts

helm template actions-runner-set \
  /tmp/arc-charts/gha-runner-scale-set \
  --namespace arc-runners \
  --set githubConfigUrl="https://github.com/YOUR_ORG/YOUR_REPO" \
  --set githubConfigSecret="arc-github-secret" \
  --set minRunners=0 \
  --set maxRunners=5 \
  --set runnerScaleSetName="k3s-self-hosted" \
  --set containerMode.type="kubernetes" \
  > argocd/team1/charts/actions-runner-set/manifests.yaml
```

### 3. Swap image references to JFrog

```bash
JFROG="your-jfrog.company.com/arc-mirror"

sed -i "s|ghcr.io/actions/|${JFROG}/ghcr.io/actions/|g" \
  argocd/team1/charts/actions-runner-controller/manifests.yaml \
  argocd/team1/charts/actions-runner-set/manifests.yaml
```

> Tip: verify all image refs with:
> `grep "image:" argocd/team1/charts/*/manifests.yaml`

### 4. Mirror images to JFrog

```bash
CHART_VERSION=0.9.3
RUNNER_VERSION=2.321.0   # check latest at https://github.com/actions/runner/releases
JFROG="your-jfrog.company.com/arc-mirror"

images=(
  "ghcr.io/actions/gha-runner-scale-set-controller:${CHART_VERSION}"
  "ghcr.io/actions/gha-runner-scale-set:${CHART_VERSION}"
  "ghcr.io/actions/actions-runner:${RUNNER_VERSION}"
)

for img in "${images[@]}"; do
  docker pull "${img}"
  docker tag  "${img}" "${JFROG}/${img}"
  docker push "${JFROG}/${img}"
done
```

---

## Cluster Prerequisites (run once on the cluster)

```bash
# 1. Create namespaces
kubectl create namespace arc-systems
kubectl create namespace arc-runners

# 2. Create the PAT secret (replace with your real token)
kubectl create secret generic arc-github-secret \
  --namespace arc-runners \
  --from-literal=github_token='ghp_YOUR_PAT_HERE'
```

PAT required scopes:
- For a **repo-level** runner: `repo`
- For an **org-level** runner: `admin:org`

---

## Deploy via ArgoCD

Commit the rendered manifests, then apply the ArgoCD Application manifests:

```bash
kubectl apply -f argocd/apps/team1/actions-runner-controller.yaml
kubectl apply -f argocd/apps/team1/actions-runner-set.yaml
```

ArgoCD will deploy the controller first. The scale-set app has no explicit wave annotation, so apply the controller app and wait for it to be healthy before syncing the runner set.

---

## Using the Runner in a Workflow

```yaml
jobs:
  build:
    runs-on: [self-hosted, k3s-self-hosted]
    steps:
      - uses: actions/checkout@v4
      - run: echo "Running on k3s!"
```

---

## Upgrading

1. On an internet-connected machine, re-run steps 1–4 above with the new `CHART_VERSION`.
2. Commit the updated `manifests.yaml` files.
3. ArgoCD auto-syncs within the next poll interval (or force-sync manually).

---

## Troubleshooting

| Symptom | Check |
|---|---|
| Runner not appearing in GitHub | `kubectl logs -n arc-systems deploy/actions-runner-controller` |
| Jobs stuck in queue | `kubectl get autoscalingrunnerset -n arc-runners` |
| Pod image pull errors | Verify image was pushed to JFrog and sed replacement was applied |
| PAT expired / insufficient scope | Rotate secret: `kubectl delete secret arc-github-secret -n arc-runners` then recreate |
