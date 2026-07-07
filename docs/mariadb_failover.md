so I do Active-passive master-master and if master goes down I do manual switchover

ATL MariaDB (primary, read_only=OFF)  ◄─── apps write here
      ↕  GTID replication both ways
LA  MariaDB (standby, read_only=ON)   ◄─── apps can read here (optional)

HAProxy → points to ATL:3306 normally


When ATL goes down — Manual Switchover Steps
# 1. On LA MariaDB — promote it
mysql -e "SET GLOBAL read_only=OFF;"
mysql -e "STOP SLAVE;"   # stop receiving from dead ATL

# 2. Update HAProxy backend to point to LA
# Edit haproxy.cfg or update the k8s ConfigMap — change server line:
#   server mariadb-primary  LA-IP:3306 check

# 3. Reload HAProxy
kubectl rollout restart deployment/haproxy -n <namespace>
# or: haproxy -sf $(cat /run/haproxy.pid)

# 4. Apps reconnect automatically via HAProxy — no app changes needed



When ATL comes back — Rejoin Steps
# On ATL — do NOT just start it writable again
# 1. Set read_only=ON on ATL
mysql -e "SET GLOBAL read_only=ON;"

# 2. Point ATL replication to LA (now primary)
mysql -e "CHANGE MASTER TO MASTER_HOST='LA-IP', MASTER_USE_GTID=slave_pos;"
mysql -e "START SLAVE;"

# 3. Wait for ATL to catch up
mysql -e "SHOW SLAVE STATUS\G"  -- check Seconds_Behind_Master = 0

# 4. Optional: switch back to ATL as primary (repeat switchover in reverse)


What you need to configure
Both nodes need log_bin and gtid_mode enabled in MariaDB config
LA node needs read_only=1 in my.cnf so it survives restarts locked
Replication user on both nodes
HAProxy backend is a ConfigMap you update manually on failover




# how tools will know where to do writes? 
Apps → HAProxy (stable endpoint, never changes) → active MariaDB primary
Apps always connect to one HAProxy address (e.g., mariadb.team1.svc:3306). You only change the HAProxy backend config on failover. Apps reconnect automatically.

How HAProxy is configured for this
Currently your HAProxy likely has a static backend. For active-passive you use a primary/backup setup:

frontend mariadb
    bind *:3306
    default_backend mariadb_primary

backend mariadb_primary
    option mysql-check user haproxy_check
    server atl-mariadb  ATL-IP:3306  check
    server la-mariadb   LA-IP:3306   check backup   # ← only used if ATL fails

The backup keyword means HAProxy automatically routes to LA if ATL health check fails — no manual HAProxy update needed on failover.

BUT — LA is still read_only=ON at the MariaDB level, so you still need to run SET GLOBAL read_only=OFF on LA manually when ATL dies.

Recommended: HAProxy backup + a simple failover script
On failover, you run one script:

#!/bin/bash
# promote-la.sh
mysql -h LA-IP -u root -p"$ROOT_PASS" -e "STOP SLAVE; SET GLOBAL read_only=OFF;"
echo "LA promoted. HAProxy will auto-route writes there."
-----------------------------------------------------------------





Do not add MaxScale immediately.

Start with:

    MariaDB GTID replication
    HAProxy as stable endpoint
    manual or scripted failover
    replication lag monitoring
    clear promotion runbook
 







Best option
MariaDB GTID-based primary-replica replication + failover automation/proxy

This usually gives the best balance of:

    reliability
    simpler operations
    predictable behavior over WAN
    easier failover than file/position replication

For Atlanta ↔ LA, this is typically better than Galera because cross-country latency makes synchronous or multi-primary approaches harder to operate.
Recommended pattern

    Atlanta = primary
    LA = replica
    GTID replication
    MaxScale, ProxySQL, or app-level failover logic
    manual or semi-automated promotion process

Why this is best
1. GTID makes failover cleaner

With GTID:

    easier to know replica position
    easier to promote replica
    easier to reattach old primary later

2. Async replication works better across distance

    less sensitive to WAN latency
    better write performance than semi-sync
    simpler than synchronous clustering

3. Easier to troubleshoot

Compared with multi-primary systems, single-primary replication is usually:

    easier to understand
    easier to recover
    less likely to hit split-brain issues

What about other options?

Option B: Semi-automated failover

Best if:

    you want faster recovery
    you can invest in monitoring and orchestration

Use:

    MaxScale
    ProxySQL
    health checks
    scripted promotion runbooks

Option C: Fully automated failover

Possible, but be careful.

Risks:

    split-brain
    false failovers during network partition
    app write confusion

Across two distant clusters, full automation needs strong fencing and clear source-of-truth logic.
My recommendation

For your setup, I’d recommend:
Primary choice

MariaDB GTID async replication + manual or semi-automated failover
Supporting tools

    MaxScale for topology awareness and routing
    or ProxySQL/HAProxy for endpoint switching
    Orchestrator-like operational logic if you build automation
    backup tooling for DR

Production-friendly architecture

    Atlanta MariaDB primary
    LA MariaDB replica
    replication monitored
    VIP/proxy/app config points to current writer
    documented promotion process
    backups in both regions
    old primary must not come back writable without rejoin procedure

Important failover rule

If you want safe failovers, prioritize:

    single writer
    GTID
    clear promotion procedure
    connection routing strategy
    split-brain prevention

Bottom line

For two k3s clusters in Atlanta and LA, the best failover-oriented option is:
MariaDB GTID primary-replica replication with one writable primary and a promotable replica

Then add:

    manual failover first
    MaxScale or ProxySQL later if you want faster failover

If you want, I can next give you:

    a recommended failover architecture diagram
    a comparison of GTID + MaxScale vs Galera
    a step-by-step failover runbook for Atlanta/LA
