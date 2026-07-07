# ProxySQL

kubectl rollout restart deployment/proxysql -n kube-system
kubectl rollout status deployment/proxysql -n kube-system

MariaDB proxy deployed in `kube-system` on both ATL and LA clusters.

## What it does
- Single connection endpoint for all MariaDB databases (port 6033)
- Routes writes to the active primary, reads to local standby (LA only)
- Detects dead backends automatically — apps reconnect without config changes
- Replaces per-database HAProxy TCP ports for app connections

## Architecture

```
External apps / HeidiSQL
  → <node-ip>:6033 (HAProxy) → proxysql.kube-system:6033

In-cluster apps
  → proxysql.kube-system.svc.cluster.local:6033

ProxySQL (ATL)                      ProxySQL (LA)
  hostgroup=0: local MariaDB          hostgroup=0: ATL NodePort:30085 (writes cross-cluster)
                                      hostgroup=1: local LA standby  (reads local)

MariaDB replication (separate path, not through ProxySQL):
  LA pod → haproxy.kube-system:3336 → ATL NodePort:30085
```

## Files
| File | Purpose |
|---|---|
| `infra/kube-system/proxysql/proxysql.yaml` | Deployment + ClusterIP Service |
| `infra/kube-system/proxysql/env_config/proxysql_cfg_dev.yaml` | ATL config (local primary) |
| `infra/kube-system/proxysql/env_config/proxysql_cfg_test.yaml` | LA config (ATL NodePort primary, local reads) |

## Required secret
```bash
kubectl create secret generic proxysql-secrets -n kube-system \
  --from-literal=admin_password='<strong-password>' \
  --from-literal=monitor_password='<same-as-repl_admin-secret>' \
  --from-literal=app5_password='<app-user-password>'
```

## Required MariaDB users (created automatically on fresh PVC via initdb)
On existing pods create once manually:
```bash
kubectl exec -it -n team1 app5-data-0 -- mariadb -u root -p"$ROOT_PASS"
```
```sql
CREATE USER IF NOT EXISTS 'proxysql_monitor'@'%' IDENTIFIED BY '<monitor_password>';
GRANT REPLICATION CLIENT, PROCESS, SELECT ON *.* TO 'proxysql_monitor'@'%';

CREATE USER IF NOT EXISTS 'app5_app'@'%' IDENTIFIED BY '<app_password>';
GRANT ALL PRIVILEGES ON `app5`.* TO 'app5_app'@'%';
FLUSH PRIVILEGES;
```

## Deploy
```bash
# Apply correct env config for the cluster first
kubectl apply -f infra/kube-system/proxysql/env_config/proxysql_cfg_dev.yaml   # ATL
# kubectl apply -f infra/kube-system/proxysql/env_config/proxysql_cfg_test.yaml  # LA

kubectl apply -f infra/kube-system/proxysql/proxysql.yaml
kubectl rollout restart deployment/proxysql -n kube-system
```

## Adding a new database
1. Create `<dbname>_app@'%'` user on the MariaDB primary
2. Add `proxysql-secrets` key: `kubectl patch secret proxysql-secrets -n kube-system ...`
3. Add server entry to `mysql_servers` in the env ConfigMap
4. Add user entry to `mysql_users` in the env ConfigMap (with `__NEWDB_PASS__` placeholder)
5. Add sed substitution for the new placeholder in `proxysql.yaml` initContainer
6. `kubectl apply` the ConfigMap + `kubectl rollout restart deployment/proxysql -n kube-system`

## Failover (ATL goes down → promote LA)
ProxySQL **detects** the failure automatically but promotion is manual:

```bash
# 1. Promote LA MariaDB to writable
kubectl exec -n team1 app5-data-0 -- \
  mariadb -u root -p"$ROOT_PASS" -e "STOP SLAVE; SET GLOBAL read_only=OFF;"

# 2. Edit proxysql_cfg_test.yaml:
#    - Comment out ATL NodePort entry (hostgroup=0)
#    - Move LA local server from hostgroup=1 to hostgroup=0

# 3. Apply and restart
kubectl apply -f infra/kube-system/proxysql/env_config/proxysql_cfg_test.yaml
kubectl rollout restart deployment/proxysql -n kube-system
# Apps reconnect automatically — no app config changes needed
```

## Rejoin ATL after recovery
```bash
# On ATL: temporarily set replHost to LA NodePort, readOnly=ON in dev.yaml values
# Then restart ATL MariaDB pod — postStart script configures replication from LA
# Once Seconds_Behind_Master=0: switchback by reversing the above
```

## HeidiSQL connection
| Field | Value |
|---|---|
| Host | `<node-ip>` (ATL: `$IP_ADDR`) |
| Port | `6033` |
| User | `app5_app` |
| Password | value of `proxysql-secrets` key `app5_password` |
| Database | `app5` |