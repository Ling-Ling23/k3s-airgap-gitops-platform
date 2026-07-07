## Key rule
 - VaultAuth.namespace + serviceAccount must refer to a ServiceAccount in the same namespace, and the Vault role must be bound to that same name/namespace combination.


 
export https_proxy="$PROXY"
export http_proxy="$PROXY"
wget -q https://github.com/hashicorp/vault-secrets-operator/archive/refs/tags/v0.10.0.tar.gz
tar -zxf v0.10.0.tar.gz
cd vault-secrets-operator-0.10.0/
unset https_proxy
unset http_proxy

kubectl apply -k config/default



### !!! NOTE: AFTER VSO IS INSTALLED AND CONFIGURED - NEED MANUALLY:
1) kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > k3s-ca.crt
2) cat k3s-ca.crt
3) kubectl get secret vault-auth-token -n kube-system -o jsonpath='{.data.token}' | base64 -d
3) copy and use both (token and crt) in vault auth method (web ui)

### GET TOKEN FOR VAULT auth
kubectl get secret vault-auth-token -n kube-system -o jsonpath='{.data.token}' | base64 -d
# crt
kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' | base64 -d > k3s-ca.crt
cat k3s-ca.crt
curl -k https://$NODE_4.net:6443/version
NEED TO USE https://$NODE_4:6443/version !!!
curl https://$NODE_1:6443/version
auth failure logs are in vault container
{"@level":"error","@message":"login unauthorized due to: Post \"https://$NODE_4.net:6443/apis/authentication.k8s.io/v1/tokenreviews\": x509: certificate is valid for kubernetes, kubernetes.default, kubernetes.default.svc, kubernetes.default.svc.cluster.local, localhost, $NODE_4, not $NODE_4.net","@module":"auth.kubernetes.auth_kubernetes_277a35f7","@timestamp":"2026-02-12T23:28:27.389348Z"}









TokenReview ServiceAccount (vault-auth in kube-system with ClusterRoleBinding to do tokenreviews)
Purpose: lets Vault server (or something acting on behalf of Vault server) call the Kubernetes TokenReview API to validate JWTs.
Workload/App ServiceAccount(s) (in the app namespace)
Purpose: identities that log in to Vault (via Kubernetes auth) and get Vault tokens with app-scoped policies.

Do you need another ServiceAccount?
If you plan to sync secrets for workloads outside kube-system (typical): yes, create a separate ServiceAccount in each target namespace (or at least one per namespace/app). That’s how you get least privilege and clean boundaries.

you can make a single Vault Kubernetes auth role that matches ServiceAccounts across all namespaces, but it’s generally not recommended because it becomes a broad “cluster-wide” Vault identity.


kubectl -n kube-system get vaultconnection vault -o yaml
kubectl -n kube-system describe vaultconnection vault
# VaultConnection exists, validate auth works
kubectl -n kube-system describe vaultauth vaultauth-kube-system
kubectl -n kube-system get vaultauth vaultauth-kube-system -o yaml
kubectl get vaultconnections -A
kubectl -n vault-secrets-operator-system logs deploy/vault-secrets-operator-controller-manager -f --tail 20

# Test secret
kubectl -n team1 get vaultstaticsecret team1-shared-app-secrets -o yaml
kubectl -n team1 describe vaultstaticsecret team1-shared-app-secrets
kubectl -n team1 get secret team1-shared-app-secrets
kubectl -n team1 describe secret team1-shared-app-secrets
print secret
kubectl -n team1 get secret team1-shared-app-secrets -o jsonpath='{.data.app_password}' | base64 -d
kubectl -n kube-system get secret my-test-config -o jsonpath='{.data.key}' | base64 -d
kubectl -n team1 get secret mongodb-secrets -o jsonpath='{.data.mongodb-key}' | base64 -d








path "k3s/*" {
  capabilities = ["read"]
}
path "auth/kubernetes/login" {
  capabilities = ["update"]
}

--- 

path "secrets/data/k3s/*" {
  capabilities = ["read"]
}
path "secrets/metadata/k3s/*" {
  capabilities = ["read", "list"]
}
path "auth/kubernetes/login" {
  capabilities = ["update"]
}
docker exec -it 320400f3aa0b vault secrets list -detailed
