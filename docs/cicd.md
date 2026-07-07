You push code change
       ↓
CI pipeline runs (GitHub Actions / GitLab CI)
  - helm dependency update
  - commits charts/*.tgz + Chart.lock back to repo
       ↓
ArgoCD detects repo change (polling or webhook)
  - syncs automatically to prod/dev/test



# Secondary repo rollout restart
Developer pushes to app4.git
        ↓
ArgoCD detects change (polling/webhook)
        ↓
team1HomeSrc resolves to new commit SHA
        ↓
global.srcRevision param changes
        ↓
pod template annotation src-revision changes
        ↓
Kubernetes detects pod spec diff → rolling restart



# The standard flow:
Code push → CI builds image (GH Actions) → pushes to registry with new tag
                                        ↓
                              ArgoCD detects tag change in values.yaml
                                        ↓
                              Rolling restart with new image




