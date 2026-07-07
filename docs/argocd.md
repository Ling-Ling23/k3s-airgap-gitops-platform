# LOGS
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller --tail=50
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=30
kubectl get application -n argocd

kubectl annotate application actions-runner-set-dev -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite

# notes
 url - https://$NODE_4.test..com:9443

 kubectl apply --server-side --force-conflicts -f install.yaml -n argocd
# pw
 kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d

# Fix ClusterRoleBindings (ArgoCD installed in default ns instead of argocd)
 kubectl patch clusterrolebinding argocd-application-controller --type=json -p='[{"op":"replace","path":"/subjects/0/namespace","value":"default"}]'
 kubectl patch clusterrolebinding argocd-applicationset-controller --type=json -p='[{"op":"replace","path":"/subjects/0/namespace","value":"default"}]'
 kubectl patch clusterrolebinding argocd-server --type=json -p='[{"op":"replace","path":"/subjects/0/namespace","value":"default"}]'

# Add git repo SSH credentials
# Get current known hosts
kubectl get configmap argocd-ssh-known-hosts-cm -n argocd \
  -o jsonpath='{.data.ssh_known_hosts}' > /tmp/known_hosts

# Append the new key
ssh-keyscan $PRIVATE_GH_FQDN 2>/dev/null >> /tmp/known_hosts

# Apply via kubectl create/replace using the file
kubectl create configmap argocd-ssh-known-hosts-cm \
  -n argocd \
  --from-file=ssh_known_hosts=/tmp/known_hosts \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment argocd-repo-server -n default



# 
kubectl rollout restart statefulset argocd-redis-ha-server -n default
kubectl rollout restart deployment argocd-redis-ha-haproxy -n default
kubectl rollout restart deployment argocd-repo-server -n default
kubectl rollout restart statefulset argocd-application-controller -n default


# if page fails - see if crd exists - kubectl get crd | grep argoproj
$TOOLING_ACCOUNT_ID@$NODE_4:~/k3s_deployment$ kubectl get crd | grep argoproj
applications.argoproj.io                      2026-03-24T21:06:06Z
applicationsets.argoproj.io                   2026-03-24T21:06:06Z
appprojects.argoproj.io                       2026-03-24T21:06:06Z

# create default AppProject if missing (fresh install)
kubectl apply -f infra/argocd/env/somethingproject...yaml

# COMMANDS
kubectl get applicationset -n argocd
kubectl get application -n argocd
## Are any cluster secrets registered with the env label?
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=cluster -o yaml | grep -E "name:|env:"
## Check ApplicationSet controller logs for errors
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-applicationset-controller --tail=50


# Repo credentials for GitHub DMZ (AUTOMATED DEPLOYMENT)
# Use one shared repo-creds secret for all repos under DMZ prefix.
# This is the default automation path; no per-app repo secret is needed.
kubectl get secret -n argocd argocd-repo-creds-github-dmz -o yaml
kubectl label secret argocd-repo-creds-github-dmz -n argocd \
  argocd.argoproj.io/secret-type=repo-creds --overwrite
kubectl -n argocd get secret argocd-repo-creds-github-dmz -o jsonpath='{.data.sshPrivateKey}' | base64 -d
# Verify URL prefix in secret data is set to:
# ssh://git@$PRIVATE_GH_FQDN/DMZ/



# How to put ssh secret to github to new applicationset (MANUAL FALLBACK - not part of automated deployment)
# Reuses the same SSH key from the existing argocd-repo-github-dmz secret:
# Extract key to temp file
kubectl get secret argocd-repo-github-dmz -n argocd \
  -o jsonpath='{.data.sshPrivateKey}' | base64 -d > /tmp/argocd_ssh_key

# Just display ssh key
inspect all keys
if manually added (old from test)
kubectl get secret argocd-repo-github-dmz -n argocd -o yaml
kubectl get secret argocd-repo-github-dmz  -n argocd -o jsonpath="{.data.sshPrivateKey}" | base64 --decode && echo
if added via vso
kubectl -n argocd get secret argocd-repo-creds-github-dmz  -o jsonpath='{.data.sshPrivateKey}' | base64 -d

# Build the secret yaml with the key properly indented
kubectl create secret generic argocd-repo-app4-src \
  -n argocd \
  --from-literal=type=git \
  --from-literal=url=ssh://git@$PRIVATE_GH_FQDN/DMZ/infrateam-app4.git \
  --from-file=sshPrivateKey=/tmp/argocd_ssh_key \
  --dry-run=client -o yaml | kubectl apply -f -

# Label it as a repo secret
kubectl label secret argocd-repo-app4-src -n argocd \
  argocd.argoproj.io/secret-type=repository

kubectl label secret argocd-repo-creds-app4 -n argocd \
  argocd.argoproj.io/secret-type=repo-creds

# Cleanup
rm /tmp/argocd_ssh_key


## HASH ISSUE FOR secondary repo
kubectl annotate application app4-dev -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite


kubectl get pod -n team1 -l app=app4-backend \
  -o jsonpath='{.items[0].metadata.annotations.src-revision}'
unknown$TOOLING_ACCOUNT_ID@$NODE_4:~$ 