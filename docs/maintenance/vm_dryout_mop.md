# VM Dryout - Method of Procedure (MOP)

This MOP describes the step-by-step procedure for safely draining ("drying out") a k3s node/VM
(e.g. for patching, maintenance, or decommissioning) while avoiding pod disruption and Longhorn
volume redundancy loss.

**Target node example used throughout:** `$NODE_3`

---

## Prerequisites

- `kubectl` access to the cluster with sufficient RBAC permissions to cordon/drain nodes.
- Access to the Longhorn UI (recommended) or `kubectl` access to the `longhorn-system` namespace.
- Identify the node and confirm it is the correct target before proceeding.

```bash
# Identify all nodes and confirm the target node name/status
kubectl get nodes -o wide
```

---

## Step 1: Cordon the target node

Mark the node unschedulable so no new pods are placed on it.

```bash
kubectl cordon <node-name>
```

## Step 2: Migrate Longhorn replicas off the node

> **Why this matters:** `kubectl drain` moves pods, but it does **not** automatically migrate
> Longhorn replicas. If the node goes down while replicas are still present, you can degrade
> volume redundancy or, worse, lose availability if the replica count/topology is tight.

In the Longhorn UI (recommended), for the cordoned node:

1. Set **Disable Scheduling** = `true`
2. Set **Eviction Requested** = `true` (node/disk eviction)
3. Wait for Longhorn to move/rebuild replicas off the node before continuing.

### Quick checks

Confirm no replicas remain scheduled on the node:

```bash
kubectl -n longhorn-system get replicas.longhorn.io -o wide | grep <node-name>
```

Confirm volume health/robustness is healthy before draining:

```bash
kubectl -n longhorn-system get volumes.longhorn.io -o custom-columns=NAME:.metadata.name,ROBUSTNESS:.status.robustness,STATE:.status.state
```

Do not proceed to Step 3 until replicas have been evacuated and volumes report `Healthy`.

## Step 3: Drain the node

Only after Longhorn replicas have been migrated, evict all pods from the node.

```bash
kubectl drain $NODE_3 \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --force \
  --timeout=60s
```

## Step 4: Perform maintenance on the VM/node

Perform the required maintenance activity (OS patching, VM shutdown, hardware work, etc.) now
that the node has no workloads or Longhorn replicas on it.

## Step 5: Uncordon the node

Once the node/VM is back up and healthy, mark it schedulable again.

```bash
kubectl uncordon $NODE_3
```

In Longhorn UI, also revert:

- **Disable Scheduling** = `false`
- **Eviction Requested** = `false`

## Step 6: Verify pods reschedule back

Confirm workloads have rescheduled onto the node as expected.

```bash
kubectl get pods -A -o wide | grep $NODE_3
```

---

## Appendix: Forcing a specific pod (e.g. Grafana) to the other node

If you need to force a specific deployment's pod off its current node (for example, to test
failover to the other node) without doing a full drain:

```bash
# Find which node grafana is on
kubectl get pod -n monitoring -l app=grafana -o wide

# Cordon that node (no new pods scheduled on it)
kubectl cordon <node-name>

# Delete the pod - scheduler will place it on the other node
kubectl delete pod -n monitoring -l app=grafana

# Uncordon after pod is running on the other node
kubectl uncordon <node-name>
```