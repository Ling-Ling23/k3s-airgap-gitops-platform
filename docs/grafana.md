# delete datasource record if changed
kubectl exec -n monitoring deploy/grafana -- rm /var/lib/grafana/grafana.db
kubectl rollout restart deployment/grafana -n monitoring

# delete containerd snapshot due to file perms
rm -rf /var/lib/rancher/k3s/agent/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/287
## Clean up any orphaned snapshot directories not tracked by containerd:
### Get all snapshot IDs known to containerd
known=$(k3s ctr snapshots --snapshotter overlayfs ls 2>/dev/null | awk 'NR>1 {print $1}')
### Find and delete orphaned dirs
for dir in /var/lib/rancher/k3s/agent/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/*/; do
    id=$(basename "$dir")
    if ! echo "$known" | grep -qx "$id"; then
        echo "Removing orphaned snapshot: $id"
        rm -rf "$dir"
    fi
done


# Remove the old image (containerd handles snapshot cleanup)
crictl rmi <image-id>


# IF I deleted too much and pods are having issue
kubectl cordon $NODE_4
On node: sudo systemctl stop k3s-agent (or k3s if it is a server node)
Validate storage: df -h ; sudo ls -ld /var/lib/rancher/k3s/agent/containerd
Rebuild containerd state (safe on a fresh node): sudo rm -rf /var/lib/rancher/k3s/agent/containerd
Ensure overlay module: sudo modprobe overlay
Start service: sudo systemctl start k3s-agent (or k3s)
kubectl uncordon $NODE_4


for dir in /var/lib/rancher/k3s/agent/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/*/; do
    id=$(basename "$dir")
    # Only process if this snapshot contains a path mentioning 'grafana'
    if find "$dir" -type d -path "*/grafana/*" | grep -q grafana; then
        if ! echo "$known" | grep -qx "$id"; then
            echo "Removing orphaned snapshot (grafana): $id"
            rm -rf "$dir"
        fi
    fi
done