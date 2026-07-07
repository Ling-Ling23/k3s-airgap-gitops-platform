# Helm Dependency Update


## GH Actions workflow
GitHub dispatches job → runner pod starts → checkout step runs
  → git clone $REPO → /home/runner/_work/
  → helm dep update runs against those cloned files
  → git push commits changes back to the repo
  → pod terminates and is deleted

> The manual steps below are obsolete. The `helm-dep-update` GitHub Actions workflow
> now handles this automatically. You only need to edit a `Chart.yaml` and push.

---

## When to run and what to change manually

### Scenario 1 — You modified `team1-common` (shared library)

Edit **only** `argocd/team1/charts/team1-common/Chart.yaml` and bump the version:

```yaml
version: 0.1.0  →  version: 0.2.0
```

Push → the workflow detects `team1-common` changed and automatically runs
`helm dependency update` for **all** app charts, then commits the updated `.tgz`
and `Chart.lock` files back to the branch.

---

### Scenario 2 — You added a new dependency to one specific app chart

Edit **only** that app's `Chart.yaml` (e.g. `app4/Chart.yaml`) to add the dependency:

```yaml
dependencies:
  - name: team1-common
    version: "0.1.0"
    repository: "file://../team1-common"
  - name: some-new-chart        # add this
    version: "1.0.0"
    repository: "https://..."
```

Push → the workflow detects that chart's `Chart.yaml` changed and runs
`helm dependency update` for **that chart only**.

---

## Force a manual run

If needed, trigger the workflow manually without changing any file:
**GitHub → Actions → Helm Dependency Update → Run workflow**

---

## What you never need to do

- Run `helm dependency update` locally
- Manually commit `.tgz` or `Chart.lock` files
- Push after every regular code change — only `Chart.yaml` changes trigger this workflow



## MANUAL VERSION JUST IN CASE
cd /home/$TOOLING_ACCOUNT_ID/k3s_deployment/
git pull

cd /home/$TOOLING_ACCOUNT_ID/k3s_deployment/argocd/team1/charts/app1
helm dependency update
git add charts/
git commit -m "add chart with library dependency"
git push

cd /home/$TOOLING_ACCOUNT_ID/k3s_deployment/argocd/team1/charts/app2
helm dependency update
git add charts/
git commit -m "add chart with library dependency"
git push

cd /home/$TOOLING_ACCOUNT_ID/k3s_deployment/argocd/team1/charts/app3
helm dependency update
git add charts/
git commit -m "add chart with library dependency"
git push

git pull
cd /home/$TOOLING_ACCOUNT_ID/k3s_deployment/argocd/team1/charts/app4
helm dependency update
git add charts/
git commit -m "add chart with library dependency - app4"
git push

cd /home/$TOOLING_ACCOUNT_ID/k3s_deployment/argocd/team1/charts/app5
helm dependency update
git add charts/
git commit -m "add chart with library dependency"
git push

cd /home/$TOOLING_ACCOUNT_ID/k3s_deployment/argocd/team1/charts/app6
helm dependency update
git add charts/
git commit -m "add chart with library dependency"
git push

cd /home/$TOOLING_ACCOUNT_ID/k3s_deployment/argocd/team1/charts/app7
helm dependency update
git add charts/
git commit -m "add chart with library dependency"
git push


cd /home/$TOOLING_ACCOUNT_ID/k3s_deployment/argocd/team1/charts/app8
helm dependency update
git add charts/
git commit -m "add chart with library dependency"
git push
