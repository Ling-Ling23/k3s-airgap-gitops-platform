# COMMANDS
SELECT user FROM mysql.user;
SHOW DATABASES;

kubectl delete statefulset dbone-data dbtwo-data -n team1
kubectl delete pvc mariadb-data-dbone-data-0 mariadb-data-dbtwo-data-0 -n team1
kubectl apply -f db_test/configmap_primary.yaml
kubectl apply -f db_test/configmap_standby.yaml
kubectl apply -f db_test/configmap_init_scripts.yaml
kubectl apply -f db_test/configmap_repl_env_primary.yaml
kubectl apply -f db_test/configmap_repl_env_standby.yaml
kubectl apply -f db_test/db_one.yaml
kubectl wait pod dbone-data-0 -n team1 --for=condition=Ready --timeout=120s
kubectl apply -f db_test/db_two.yaml
# After both up (run on secondary, but if primary was up first - very likely replication is now set with slave init procedure ):
kubectl exec -n team1 app5-data-0 -- bash /usr/local/bin/setup-replication.sh
kubectl exec -n team1 app1-data-0 -- bash /usr/local/bin/setup-replication.sh
kubectl exec -n team2 app7-data-0 -- bash /usr/local/bin/setup-replication.sh
kubectl exec -n team1 app8-data-0 -- bash /usr/local/bin/setup-replication.sh

# Debug:
kubectl exec -n team1 dbtwo-data-0 -- bash /usr/local/bin/setup-replication.sh
kubectl exec -n team1 dbtwo-data-0 -- mariadb -u root -p"test" -e "SHOW SLAVE STATUS\G"
kubectl exec -n team1 dbone-data-0 -- mariadb -u root -p"test" -e "SHOW SLAVE STATUS\G"
kubectl exec -n team1 app5-data-0 -- mariadb -u root -p"" -e "SHOW SLAVE STATUS\G"
kubectl exec -n team2 app7-data-0 -- mariadb -u root -p'' -e "SHOW SLAVE STATUS\G"
kubectl exec -n team2 app7-data-0 -- mariadb -u root -p'' -e "SHOW DATABASES;\G"









# Migration error fix (ERROR 1030 (HY000) at line 47: Got error 1 "Operation not permitted" from storage engine InnoDB):
## Note
The real suspect is innodb_buffer_pool_size_max=128m seen in the logs. A single INSERT with 179K rows hits the undo log/buffer pool limit. Try splitting the INSERT into smaller batches:
## On the k3s node — split into ~5000-row chunks and import
kubectl exec -n team1 app1-data-0 -- bash -c \
  "mariadb -u root -p'$ROOT_PASS' app1 -e 'SET GLOBAL innodb_buffer_pool_size=536870912;'"
## Extract just the big INSERT and split into chunks of 1000 rows each
grep -n "^INSERT" app1.sql   # confirm it's one big INSERT
## Use awk to split into 1000-row inserts
awk 'BEGIN{f=0} /INSERT INTO/{f=1} f{
  if(NR%1000==0){print ";"} print
}' app1.sql > /tmp/app1_split.sql





# Deletes
k delete statefulset app5-data -n team1
kubectl delete pvc mariadb-data-app5-data-0  -n team1
k delete statefulset app8-data -n team1
kubectl delete pvc mariadb-data-app8-data-0  -n team1
k delete statefulset app7-data -n team2
kubectl delete pvc mariadb-data-app7-data-0  -n team2

# dbone / dbtwo MariaDB Replication — Setup & Failover Runbook

---

## Architecture

```
dbone (primary)                         dbtwo (standby)
────────────────────                    ────────────────────
StatefulSet: dbone-data                 StatefulSet: dbtwo-data
ConfigMap:   configmap_primary          ConfigMap:   configmap_standby
server_id:   1  /  gtid_domain_id: 1   server_id:   2  /  gtid_domain_id: 2
auto_incr:   1, 3, 5, 7...  (offset=1) auto_incr:   2, 4, 6, 8...  (offset=2)
read_only:   OFF  ← apps write here    read_only:   ON
NodePort:    30336                      NodePort:    30337
```

**Topology:** active-passive master-master. Both replicate each other's binlogs
so either can be promoted. Only dbone accepts writes at any time.

**Same-cluster test:** dbtwo in same k3s cluster, replication via headless DNS + port 3306.
**Production (ATL/LA):** two separate k3s clusters, replication via NodePort 30336/30337.

---

## Files Reference

| File | Purpose |
|---|---|
| `configmap_primary.yaml` | MariaDB config for dbone (server_id=1, domain=1, read_only=OFF) |
| `configmap_standby.yaml` | MariaDB config for dbtwo (server_id=2, domain=2, read_only=ON) |
| `configmap_init_scripts.yaml` | Shared: initdb user creation + postStart replication script |
| `configmap_repl_env_primary.yaml` | dbone env: REPL_HOST → dbtwo, REPL_PORT |
| `configmap_repl_env_standby.yaml` | dbtwo env: REPL_HOST → dbone, REPL_PORT |
| `db_one.yaml` | dbone StatefulSet |
| `db_two.yaml` | dbtwo StatefulSet |
| `svc_db_one.yaml` | dbone headless service (in-cluster DNS) |
| `svc_db_one_nodeport.yaml` | dbone NodePort 30336 (HeidiSQL / cross-cluster) |
| `svc_db_two.yaml` | dbtwo headless service |
| `svc_db_two_nodeport.yaml` | dbtwo NodePort 30337 |

---

## Secrets Used

Both pods read from existing secret `team1-database-roots`:

| Key | Used as |
|---|---|
| `dbone` | `MYSQL_ROOT_PASSWORD` on dbone pod |
| `dbone` | `MYSQL_ROOT_PASSWORD` on dbtwo pod (reused for dev) |
| `repl_admin` | `REPL_PASSWORD` — password for `replicator` user (remote binlog access) |
| `repl_admin` | `REPL_ADMIN_PASSWORD` — password for `repl_admin` user (local slave control) |

---

## How Automation Works

### On first pod start (empty PVC) — initdb
MariaDB entrypoint sources `/docker-entrypoint-initdb.d/01-create-replication-user.sh`:
- Creates `replicator@'%'` with `REPLICATION SLAVE, REPLICATION CLIENT, SELECT, RELOAD, LOCK TABLES`
- Creates `repl_admin@'localhost'` with `REPLICATION SLAVE ADMIN` only

### On every pod start — postStart hook
Kubernetes runs `/usr/local/bin/setup-replication.sh`:
1. Waits up to 2 minutes for local MariaDB socket
2. Skips if `REPL_HOST` env is not set
3. Skips if slave is already `Yes` or `Connecting` (idempotent)
4. Fetches `@@gtid_current_pos` from master via `replicator` user
5. Runs `RESET MASTER` then `SET GLOBAL gtid_slave_pos` to master's position
6. If master has data and local DB is empty → seeds via `mariadb-dump --databases dbone --gtid`
7. Runs `CHANGE MASTER TO` + `START SLAVE`
8. Always exits 0 — never crashes the pod

### Users summary

| User | Host | Privileges | Used by |
|---|---|---|---|
| `root` | `localhost` | All | initdb only (first boot) |
| `replicator` | `%` | REPLICATION SLAVE, CLIENT, SELECT, RELOAD, LOCK TABLES | Remote server pulls binlog + dump seeding |
| `repl_admin` | `localhost` | REPLICATION SLAVE ADMIN | postStart hook — local slave management only |

---

## Part 1 — Initial Deployment

### ⚠ Deploy dbone FIRST, wait for Ready, then deploy dbtwo

**Why:** dbtwo's postStart script connects to dbone to seed data and get the GTID position.
If dbtwo starts first, dbone is unreachable and no replication is configured on dbtwo.

### Step 1 — Configure REPL_HOST (same-cluster test)

[db_test/configmap_repl_env_primary.yaml](configmap_repl_env_primary.yaml):
```yaml
data:
  REPL_HOST: "dbtwo-data-0.dbtwo-mariadb.team1.svc.cluster.local"
  REPL_PORT: "3306"
```

[db_test/configmap_repl_env_standby.yaml](configmap_repl_env_standby.yaml):
```yaml
data:
  REPL_HOST: "dbone-data-0.dbone-mariadb.team1.svc.cluster.local"
  REPL_PORT: "3306"
```

> For production (ATL/LA cross-cluster): set `REPL_HOST` to the remote k3s node IP and `REPL_PORT` to `30336`/`30337`.

### Step 2 — Apply all manifests

```bash
kubectl apply -f db_test/configmap_primary.yaml
kubectl apply -f db_test/configmap_standby.yaml
kubectl apply -f db_test/configmap_init_scripts.yaml
kubectl apply -f db_test/configmap_repl_env_primary.yaml
kubectl apply -f db_test/configmap_repl_env_standby.yaml
kubectl apply -f db_test/svc_db_one.yaml
kubectl apply -f db_test/svc_db_one_nodeport.yaml
kubectl apply -f db_test/svc_db_two.yaml
kubectl apply -f db_test/svc_db_two_nodeport.yaml

# Deploy dbone first
kubectl apply -f db_test/db_one.yaml
kubectl wait pod dbone-data-0 -n team1 --for=condition=Ready --timeout=180s

# Then dbtwo — postStart will seed from dbone automatically
kubectl apply -f db_test/db_two.yaml
```

### Step 3 — Verify replication

```bash
# dbtwo → dbone (primary direction, must be Yes)
kubectl exec -n team1 dbtwo-data-0 -- \
  mariadb -u root -p"$ROOT_PASS" -e "SHOW SLAVE STATUS\G" \
  | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind|Last_Error"

# dbone → dbtwo (configured after dbtwo comes up, needed for failover rejoin)
kubectl exec -n team1 dbone-data-0 -- \
  mariadb -u root -p"$ROOT_PASS" -e "SHOW SLAVE STATUS\G" \
  | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind|Last_Error"

# Verify data seeded on dbtwo
kubectl exec -n team1 dbtwo-data-0 -- \
  mariadb -u root -p"$ROOT_PASS" -e "SHOW TABLES IN dbone;"
```

---

## Part 2 — If Pods Already Exist (no PVC wipe)

initdb won't re-run. Replication users must be created manually once:

```bash
# On dbone
kubectl exec -n team1 dbone-data-0 -- \
  mariadb -u root -p"$ROOT_PASS" -e "
    CREATE USER IF NOT EXISTS 'replicator'@'%' IDENTIFIED BY '$REPL_PASS';
    GRANT REPLICATION SLAVE, REPLICATION CLIENT, SELECT, RELOAD, LOCK TABLES ON *.* TO 'replicator'@'%';
    CREATE USER IF NOT EXISTS 'repl_admin'@'localhost' IDENTIFIED BY '$REPL_PASS';
    GRANT REPLICATION SLAVE ADMIN ON *.* TO 'repl_admin'@'localhost';
    FLUSH PRIVILEGES;"

# On dbtwo (same commands)
kubectl exec -n team1 dbtwo-data-0 -- \
  mariadb -u root -p"$ROOT_PASS" -e "
    CREATE USER IF NOT EXISTS 'replicator'@'%' IDENTIFIED BY '$REPL_PASS';
    GRANT REPLICATION SLAVE, REPLICATION CLIENT, SELECT, RELOAD, LOCK TABLES ON *.* TO 'replicator'@'%';
    CREATE USER IF NOT EXISTS 'repl_admin'@'localhost' IDENTIFIED BY '$REPL_PASS';
    GRANT REPLICATION SLAVE ADMIN ON *.* TO 'repl_admin'@'localhost';
    FLUSH PRIVILEGES;"

# Then restart pods to trigger postStart
kubectl delete pod dbone-data-0 -n team1
kubectl wait pod dbone-data-0 -n team1 --for=condition=Ready --timeout=180s
kubectl delete pod dbtwo-data-0 -n team1
```

---

## Part 3 — Monitoring Replication Lag

```bash
kubectl exec -n team1 dbtwo-data-0 -- \
  mariadb -u root -p"$ROOT_PASS" -e "SHOW SLAVE STATUS\G" \
  | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master|Last_Error"
```

| Field | Expected |
|---|---|
| `Slave_IO_Running` | Yes |
| `Slave_SQL_Running` | Yes |
| `Seconds_Behind_Master` | 0 or very low |
| `Last_Error` | (empty) |

**Binlog retention:** `expire_logs_days = 7` — if dbtwo is down > 7 days, binlogs
on dbone may be purged. Check before reconnecting:
```bash
kubectl exec -n team1 dbone-data-0 -- \
  mariadb -u root -p"$ROOT_PASS" -e "SHOW BINARY LOGS;"
```
If required logs are missing → full re-seed needed (wipe dbtwo PVC and redeploy).

---

## Part 4 — Failover: dbone goes down → Promote dbtwo

### Step 1 — Promote dbtwo

```bash
kubectl exec -it -n team1 dbtwo-data-0 -- \
  mariadb -u root -p"$ROOT_PASS" -e "STOP SLAVE; SET GLOBAL read_only=OFF;"
```

> `read_only=OFF` is in-memory — survives until pod restart.
> To make permanent: update `configmap_standby.yaml` → `read_only = OFF` and re-apply.

### Step 2 — Point apps to dbtwo

Update HAProxy backend to dbtwo's NodePort IP:
```bash
kubectl edit configmap haproxy-config -n <haproxy-namespace>
# change: server mariadb-primary  <NODE_IP>:30337  check
kubectl rollout restart deployment/haproxy -n <haproxy-namespace>
```

### Step 3 — Verify dbtwo accepts writes

```bash
kubectl exec -it -n team1 dbtwo-data-0 -- \
  mariadb -u root -p"$ROOT_PASS" -e "INSERT INTO dbone.failover_test VALUES (NOW());"
```

---

## Part 5 — Rejoin dbone after Recovery

```bash
kubectl exec -it -n team1 dbone-data-0 -- mariadb -u root -p"$ROOT_PASS"
```

```sql
-- 1. Start read-only — don't accept writes until caught up
SET GLOBAL read_only=ON;

-- 2. Point dbone to replicate from dbtwo (now the active primary)
STOP SLAVE;
CHANGE MASTER TO
  MASTER_HOST     = 'dbtwo-data-0.dbtwo-mariadb.team1.svc.cluster.local',
  MASTER_PORT     = 3306,
  MASTER_USER     = 'replicator',
  MASTER_PASSWORD = '<repl_admin secret value>',
  MASTER_USE_GTID = slave_pos;
START SLAVE;

-- 3. Wait until fully caught up (Seconds_Behind_Master = 0)
SHOW SLAVE STATUS\G

-- 4. Optional: switch primary back to dbone (reverse steps above)
```

Alternatively, just restart dbone's pod — postStart will detect dbtwo is running,
seed if needed, configure `CHANGE MASTER TO` dbtwo, and start the slave automatically.

---

## Part 6 — Optional Switchback to dbone as Primary

```sql
-- On dbone (after Seconds_Behind_Master = 0):
STOP SLAVE;
SET GLOBAL read_only=OFF;

-- On dbtwo:
SET GLOBAL read_only=ON;
```

Update HAProxy to point back to dbone NodePort 30336, reload.

---

## Quick Reference

| Action | Command |
|---|---|
| Check replication status | `SHOW SLAVE STATUS\G` |
| Stop replication | `STOP SLAVE;` |
| Start replication | `START SLAVE;` |
| Make node writable | `SET GLOBAL read_only=OFF;` |
| Make node read-only | `SET GLOBAL read_only=ON;` |
| Check server_id / domain | `SHOW VARIABLES LIKE 'server_id'; SHOW VARIABLES LIKE 'gtid_domain_id';` |
| Check binlog position | `SHOW MASTER STATUS;` |
| Check GTID state | `SELECT @@gtid_current_pos; SELECT @@gtid_slave_pos;` |
| Run setup script manually | `kubectl exec -n team1 <pod> -- bash /usr/local/bin/setup-replication.sh` |
| Get repl password | `kubectl get secret team1-database-roots -n team1 -o jsonpath='{.data.repl_admin}' \| base64 -d` |

---

## GTID & Auto-Increment Design

**Why separate `gtid_domain_id`:**
Both servers share the same domain `0` by default. With `gtid_strict_mode=ON`,
sequence numbers must be monotonically increasing within a domain. dbtwo's own
initdb transactions would conflict with dbone's replication events in the same domain.
Setting `domain_id=1` for dbone and `domain_id=2` for dbtwo keeps their sequences
entirely independent — no conflicts possible.

**Why `auto_increment_increment=2` with different offsets:**
Prevents duplicate primary key collisions if writes happen on both nodes simultaneously
(e.g. during failover overlap):
- dbone generates: 1, 3, 5, 7, 9...
- dbtwo generates: 2, 4, 6, 8, 10...

In normal active-passive operation (all writes go to dbone via HAProxy) this never
triggers — but it's a safety net for the failover window.

