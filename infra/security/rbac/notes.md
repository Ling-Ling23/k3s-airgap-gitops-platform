using SSH local users you can still do RBAC in k3s, but the mapping is indirect: you create a Kubernetes identity per person (typically via client certificates) and give each person a kubeconfig. Their Linux/SSH account is just how they log into a machine; Kubernetes RBAC applies to the identity in the kubeconfig.
Approach: client-certificate users (fits k3s embedded setup)
1) Create a key + CSR for a user

On an admin machine (or server node):

bash
Copy Code

USER=alice

GROUP=devs


openssl genrsa -out ${USER}.key 2048


openssl req -new -key ${USER}.key -out ${USER}.csr \

  -subj "/CN=${USER}/O=${GROUP}"

2) Submit CSR to Kubernetes and approve

bash
Copy Code

kubectl apply -f - <<EOF

apiVersion: certificates.k8s.io/v1

kind: CertificateSigningRequest

metadata:

  name: ${USER}

spec:

  request: $(base64 -w0 < ${USER}.csr)

  signerName: kubernetes.io/kube-apiserver-client

  expirationSeconds: 31536000

  usages:

  - client auth

EOF


kubectl certificate approve ${USER}

Fetch the signed cert:

bash
Copy Code

kubectl get csr ${USER} -o jsonpath='{.status.certificate}' | base64 -d > ${USER}.crt

3) Create RBAC for that user (example: read pods in a namespace)

bash
Copy Code

NAMESPACE=default


kubectl -n ${NAMESPACE} create role pod-reader \

  --verb=get,list,watch --resource=pods


kubectl -n ${NAMESPACE} create rolebinding ${USER}-pod-reader \

  --role=pod-reader --user=${USER}

(You can also bind by group using --group=devs if you want to manage many users at once.)
4) Generate a kubeconfig for the user

Get cluster info from your existing admin kubeconfig:

bash
Copy Code

CLUSTER_NAME=$(kubectl config view -o jsonpath='{.contexts[?(@.name=="'$(kubectl config current-context)'")].context.cluster}')

SERVER=$(kubectl config view -o jsonpath='{.clusters[?(@.name=="'${CLUSTER_NAME}'")].cluster.server}')

CA_DATA=$(kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="'${CLUSTER_NAME}'")].cluster.certificate-authority-data}')

Create kubeconfig:

bash
Copy Code

cat > ${USER}.kubeconfig <<EOF

apiVersion: v1

kind: Config

clusters:

- name: ${CLUSTER_NAME}

  cluster:

    server: ${SERVER}

    certificate-authority-data: ${CA_DATA}

users:

- name: ${USER}

  user:

    client-certificate-data: $(base64 -w0 < ${USER}.crt)

    client-key-data: $(base64 -w0 < ${USER}.key)

contexts:

- name: ${USER}@${CLUSTER_NAME}

  context:

    cluster: ${CLUSTER_NAME}

    user: ${USER}

current-context: ${USER}@${CLUSTER_NAME}

EOF

Give ${USER}.kubeconfig to that Linux user (e.g., copy to their home and set KUBECONFIG=~/.kube/config).
5) Test as the user

bash
Copy Code

kubectl --kubeconfig ${USER}.kubeconfig auth can-i list pods -n default

kubectl --kubeconfig ${USER}.kubeconfig get pods -n default

Notes / gotchas

    This does not automatically use Linux accounts; it just lets you issue Kubernetes credentials to match them (same name).
    If users share a node, avoid sharing kubeconfigs/keys (file permissions matter).
    If you want “login with SSH user automatically becomes Kubernetes user”, that requires an external auth layer (OIDC/webhook). With embedded k3s and local SSH users, certs are the standard path.
