# Helm Charts — Dependency Management

## Overview

This directory contains the Helm charts for all `team1` applications:

| Chart | Description |
|---|---|
| `app1` | app1 application |
| `app2` | CBB Links application |
| `app3` | app3 application |
| `app4` | team1 Home portal |
| `app5` | team1 Mini Applications |
| `app6` | team1 Warehouse |
| `app7` | app7 application |
| `app8` | PCI Tool application |
| `team1-common` | **Shared library chart** (dependency for all charts above) |

---

## Why `helm dependency update` is Required

Every application chart declares `team1-common` as a dependency in its `Chart.yaml`:

```yaml
# Example: app4/Chart.yaml
dependencies:
  - name: team1-common
    version: "0.1.0"
    repository: "file://../team1-common"
```

Helm **cannot** read a dependency directly from a sibling folder at render or deploy time —
not locally, and not in ArgoCD. Before a chart can be used, all its dependencies must be
**pre-packaged** and placed inside the chart's own `charts/` subdirectory.

`helm dependency update` does exactly this:

1. Resolves the `file://../team1-common` reference.
2. Packages `team1-common` into a `.tgz` archive.
3. Drops the archive into `<chart>/charts/team1-common-0.1.0.tgz`.
4. Writes/updates `Chart.lock` with a SHA-256 digest and a timestamp.

ArgoCD then syncs this self-contained chart (including the bundled `.tgz`) without needing
to resolve any external or local paths at deploy time.

---

## Why a `.tgz` File?

This is Helm's standard dependency bundling format. Packaging dependencies as `.tgz`
archives makes a chart fully portable and self-sufficient — no network calls, no local path
resolution, no external registries required at render time. Even `file://` local
dependencies are packaged the same way.

The `.tgz` files under `<chart>/charts/` are committed to Git intentionally so that
ArgoCD can use the chart without running Helm locally.

---

## Will Re-running Produce a Different File Even With No Code Changes?

**Yes.** Even if `team1-common` is completely untouched, re-running
`helm dependency update` will produce changes:

| File | What changes | Why |
|---|---|---|
| `Chart.lock` | `generated:` timestamp | Always set to current time |
| `charts/*.tgz` | Archive byte content | Tar stores file modification times; gzip output varies |

This means a `git diff` will show the `.tgz` and `Chart.lock` as modified even though no
actual logic changed. These are **noisy, meaningless commits**.

---

## When Should You Run `helm dependency update`?

Run it **only** when one of the following is true:

| Situation | Run? |
|---|---|
| You modified `team1-common` templates, helpers, or `Chart.yaml` | **Yes** |
| You bumped the `version` field in `team1-common/Chart.yaml` | **Yes** |
| You added a new external dependency to an app chart's `Chart.yaml` | **Yes** |
| You changed app templates, values, or config with no dependency change | **No** |
| Routine "just in case" run with nothing changed | **No** |

---

## Manual Workflow (when update is needed)

```bash
# 1. Pull latest before making any changes
git pull

# 2. Make your changes to team1-common (or an app chart's Chart.yaml)

# 3. For each chart that depends on what you changed:
cd argocd/team1/charts/app4
helm dependency update
git add charts/
git commit -m "chore: helm dependency update for app4"
git push
```

The GitHub Actions workflow (`helm-dependency-update.yml`) automates this for CI — it
detects which charts actually need updating and skips everything else.

---

## Directory Structure per Chart

```
<chart-name>/
├── Chart.yaml        # Chart metadata + dependency declarations
├── Chart.lock        # Locked dependency versions + digest (committed to Git)
├── charts/
│   └── team1-common-0.1.0.tgz   # Packaged dependency (committed to Git)
├── templates/        # Kubernetes manifests (uses helpers from team1-common)
└── values/           # Environment-specific values files
```
