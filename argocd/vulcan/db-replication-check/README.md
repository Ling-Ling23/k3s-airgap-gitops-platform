# DB Replication Check CronJob

Periodically runs `SHOW MASTER STATUS` and `SHOW SLAVE STATUS` against every
MariaDB StatefulSet in the cluster and logs one machine-parseable line per
database. Reuses the existing `mariadb:11.8.5` image (no custom image build)
and the existing `team1-database-roots` / `team2-database-roots` secrets
(no new DB users required).

## Apply

```bash
kubectl apply -f monitoring/db-replication-check/configmap_check_replication_script.yaml
kubectl apply -f monitoring/db-replication-check/cronjob_team1_tools.yaml
kubectl apply -f monitoring/db-replication-check/cronjob_team2.yaml
```

## Trigger a run immediately (don't wait for the schedule)

```bash
kubectl create job --from=cronjob/db-replication-check -n team1 db-replication-check-manual-$(date +%s)
kubectl create job --from=cronjob/db-replication-check -n team2 db-replication-check-manual-$(date +%s)
```

## Read results

```bash
kubectl get jobs -n team1 -l app=db-replication-check
kubectl logs -n team1 job/<job-name>
```

Each database prints one line like:

```
STATUS name=app5 result=OK slave_io=Yes slave_sql=Yes seconds_behind=0 master_log=mariadb-bin.000123:456 last_error=""
STATUS name=app8 result=BROKEN slave_io=No slave_sql=Yes seconds_behind=NA master_log=mariadb-bin.000045:891 last_error="..."
STATUS name=dbtwo result=NO_REPLICA master_log=mariadb-bin.000001:328
```

## Add / remove a database

Edit `DB_TARGETS` in [cronjob_team1_tools.yaml](cronjob_team1_tools.yaml) or
[cronjob_team2.yaml](cronjob_team2.yaml). Format: `name=secretkey,...` where
`name` matches the StatefulSet's app name (`<name>-data-0.<name>-mariadb.<ns>.svc.cluster.local`)
and `secretkey` is the key in the mounted root-password secret.

## What triggers an alert

Each check pushes `mysql_replication_healthy{namespace,db}` (0/1) to the
Prometheus Pushgateway, which Prometheus scrapes and alerts on via the
existing Alertmanager `flask-api` webhook — no new receiver needed.

| Result | Meaning | `healthy` | Alerts? |
|---|---|---|---|
| `OK` | Slave running normally (`Slave_IO_Running`/`Slave_SQL_Running` = Yes) | 1 | No |
| `NO_REPLICA` | Master with no slave attached — expected for primary-only DBs | 1 | No |
| `BROKEN` | Slave configured but IO or SQL thread not running | 0 | **Yes** |
| `UNREACHABLE` | Could not connect to the database at all | 0 | **Yes** |
| `NO_SECRET` | Root password key missing from the mounted secret | 0 | **Yes** |
| *(no push in 30m)* | CronJob may not be running/pushing | — | **Yes** (`MySQLReplicationCheckStale`) |

In short: a healthy slave or a master working as designed (no slave attached)
never alerts — only an actual broken/unreachable/misconfigured database does.

A separate gauge `mysql_replication_configured` (1 if a slave row exists, 0
for `NO_REPLICA`) is pushed for dashboard visibility only — it isn't alerted
on. Query current values directly:
```bash
kubectl port-forward -n monitoring svc/prometheus-pushgateway 9091:9091
curl -s http://localhost:9091/metrics | grep mysql_replication
```

## Why no custom image / why root

- The `mariadb:11.8.5` image is already pulled on every node for the
  StatefulSets — reusing it avoids any new registry/build/maintenance work.
- `kubectl exec` into each pod was avoided in favor of connecting over the
  cluster network (same headless-service DNS pattern the replication
  postStart script already uses), so this also works if you later point it
  at remote NodePorts for cross-cluster (ATL/LA) checks.
- Root was reused per your call — for tighter security later, swap it for a
  dedicated `repl_monitor@'%'` user with only `REPLICATION CLIENT`, added
  next to `replicator`/`repl_admin` in
  [db_test/configmap_init_scripts.yaml](../../db_test/configmap_init_scripts.yaml).
