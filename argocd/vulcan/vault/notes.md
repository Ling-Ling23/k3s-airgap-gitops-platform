kubectl rollout restart statefulset vault -n kube-system
kubectl -n kube-system scale statefulset/vault --replicas=0

# pvc stuck after deletion due to finalizer
 kubectl delete pvc vault-data-vault-0 -n kube-system
 kubectl patch pvc vault-data-vault-0 -n kube-system -p '{"metadata":{"finalizers":null}}'
 persistentvolumeclaim/vault-data-vault-0 patched
 Why it happens: Kubernetes adds pvc-protection finalizer to prevent deletion while a pod is using the volume. If the pod or volume attachment is in  a broken state, the finalizer never gets cleaned up automatically — you have to force it.
## Also might help to restart longhorn provisioner
    kubectl rollout restart deployment csi-provisioner -n longhorn-system

# Checks
kubectl get node.longhorn.io $NODE_6 -n longhorn-system -o yaml | grep -E "schedulable|diskUUID|storageAvailable"
kubectl describe volume.longhorn.io pvc-ae12f958-3ca1-44af-ac46-2c0d76046231 -n longhorn-system | grep -E "State|Robustness|Node"
kubectl describe replica.longhorn.io pvc-c84ff9f5-851e-4228-bc72-064b3517ab0a-r-c7da9d84 -n longhorn-system | grep -A5 -E "State|Message|Error|Cond
 kubectl logs -n longhorn-system longhorn-manager-klpvn --tail=100 | grep -E "error|Error"
kubectl logs -n longhorn-system -l app=csi-attacher --tail=50 | grep -E "error|Error"
kubectl get volumeattachment | grep -E "ae12f958|5b8f1519"



# vault

Verify the new node is reachable from other node:
curl -sk https://$NODE_6.test..com:30820/v1/sys/seal-status

Check connectivity from inside the pod to Swarm nodes
kubectl exec -it vault-0 -n kube-system -- sh
wget -qO- --no-check-certificate https://$NODE_7.web..com:8200/v1/sys/health




# Firewall requirements for raft join
# Port 30820 = Vault API (must be open for unseal and client access)
# Port 30821 = Vault raft cluster port (must be open for leader to call back to new node)
# If 30821 is blocked: join request reaches leader but leader can't connect back → silent failure
# Symptom: "failed to retry join raft cluster" every 2s, no logs on leader, join takes ~60ms
# Fix on $NODE_6:
#   sudo firewall-cmd --add-port=30821/tcp --permanent && sudo firewall-cmd --reload
# Verify from leader node:
#   curl -sk --max-time 5 https://$NODE_6.test..com:30821 -i  # must return something

# delete for temp fix
k delete -f argocd/apps/vulcan/vault.yaml 
kubectl delete pvc vault-data-vault-0 -n kube-system
kubectl patch pvc vault-data-vault-0 -n kube-system -p '{"metadata":{"finalizers":null}}'
kaf argocd/apps/vulcan/vault.yaml 
curl -sk https://$NODE_6.test..com:30820/v1/sys/seal-status

curl -sk --request PUT --data '{"key": ""}' https://$NODE_6.test..com:30820/v1/sys/unseal -i

# NEXT
cronjob to autounseal

