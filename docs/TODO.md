# TO DO
## VAULT
    [x] cronjob to autounseal
    [ ] retry join on swarm - update vault cfg
## ARGOCD
    [x] can we monitor two repos for apps? yes, is it worth?
    [x] better way to manage ssh to gh from argocd apps
## OTHERS
    [x] promtail to alloy
    [x] Resilience & HA -> HAProxy replicas — Your haproxy.yaml has replicas: 1. This is a single point of failure for all ingress (443, 8443, 9443, 3306, 8220). Consider scaling to 2+ with a PodDisruptionBudget and topologySpreadConstraints across nodes.



Security
NetworkPolicies — You have namespaces with ResourceQuotas and RBAC, but no NetworkPolicy manifests exist anywhere. You should add default-deny ingress/egress policies per namespace with explicit allow rules. This is especially important given you have MongoDB, PCI-related tools (app8), and Vault co-existing.

Pod Security Standards (PSS) — No pod-security.kubernetes.io labels on your namespaces. Add enforce: restricted or at minimum enforce: baseline on the team1, logging, monitoring namespaces. PSPs are gone in k3s 1.25+.

RBAC coverage — You only have two RBAC files in rbac. Consider auditing what service accounts your apps use and applying least-privilege roles instead of relying on default ServiceAccounts.

PodDisruptionBudgets (PDB) — No PDBs exist anywhere in the repo. Add them for critical workloads (haproxy, ArgoCD, Vault, MongoDB, Grafana) to prevent simultaneous eviction during node drain/upgrade.

Longhorn backup target — Your longhorn.yaml is a full install manifest (v1.6.2). Verify a backup target (NFS/S3) is configured in Longhorn settings — if it's only configured in the UI it won't survive a Longhorn reinstall.

ArgoCD AppProject scoping — All apps appear to use project: default, which has no restrictions. Create dedicated AppProject resources with sourceRepos, destinations, and clusterResourceWhitelist scoped per team/namespace to prevent lateral movement via ArgoCD.
NOTE: I think we are good with what I have

Cert expiry management — You mount TLS certs as Kubernetes secrets (team1-certs). There's no cert-manager or renewal automation visible. If these are manually renewed, add a Prometheus alert or a CronJob/cert-manager Certificate resource to alert on expiry.
