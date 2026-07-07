{{- define "team1-common.database.initscripts" -}}
{{- if .Values.database.enabled }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Values.config.k3sAppName }}-init-scripts
  namespace: {{ .Values.namespace }}
  labels:
    app: {{ .Values.config.k3sAppName }}-database
data:
  # Runs once on first DB init (when PVC is empty).
  # MariaDB entrypoint sources .sh files in /docker-entrypoint-initdb.d/
  # so MYSQL_ROOT_PASSWORD and REPL_PASSWORD env vars are available.
  01-create-replication-user.sh: |
    #!/bin/bash
    set -e
    echo "[init] Creating replication users..."
    mariadb -u root -p"${MYSQL_ROOT_PASSWORD}" <<-EOSQL
      -- replicator: used by the REMOTE server to connect to this node's binlog
      -- REPLICATION CLIENT allows querying master's GTID position from the setup script
      -- SELECT + RELOAD + LOCK TABLES allow mariadb-dump for initial seeding
      CREATE USER IF NOT EXISTS 'replicator'@'%' IDENTIFIED BY '${REPL_PASSWORD}';
      GRANT REPLICATION SLAVE, REPLICATION CLIENT, SELECT, RELOAD, LOCK TABLES ON *.* TO 'replicator'@'%';

      -- repl_admin: used LOCALLY by setup-replication.sh to run CHANGE MASTER / START SLAVE
      -- Has only REPLICATION SLAVE ADMIN — cannot read data, cannot write data
      CREATE USER IF NOT EXISTS 'repl_admin'@'localhost' IDENTIFIED BY '${REPL_ADMIN_PASSWORD}';
      GRANT REPLICATION SLAVE ADMIN ON *.* TO 'repl_admin'@'localhost';

      -- proxysql_monitor: used by ProxySQL to health-check this backend
      CREATE USER IF NOT EXISTS 'proxysql_monitor'@'%' IDENTIFIED BY '${PROXYSQL_MONITOR_PASSWORD}';
      GRANT REPLICATION CLIENT, PROCESS, SELECT ON *.* TO 'proxysql_monitor'@'%';

      -- app user: used by applications and ProxySQL to connect to this database
      -- Named <appname>_app to avoid root@% which MariaDB restricts to localhost
      CREATE USER IF NOT EXISTS '${APP_USER}'@'%' IDENTIFIED BY '${APP_USER_PASSWORD}';
      GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${APP_USER}'@'%';

      FLUSH PRIVILEGES;
    EOSQL
    echo "[init] Replication users created."

  # Mounted to /usr/local/bin and called from the postStart lifecycle hook.
  # Runs on every pod start but is fully idempotent:
  #   - Waits for local MariaDB to be ready
  #   - Skips if REPL_HOST is not set
  #   - Skips if replication is already running
  setup-replication.sh: |
    #!/bin/bash
    # No set -e — this script must always exit 0.
    # A non-zero exit from postStart kills the pod (FailedPostStartHook).
    # Only the readiness wait is fatal; everything else logs and exits 0.

    # repl_admin has only REPLICATION SLAVE ADMIN — never root in postStart
    MYSQL_CMD="mariadb -u repl_admin -p${REPL_ADMIN_PASSWORD} --connect-timeout=5"
    # root is only needed to check readiness (repl_admin exists after initdb)
    MYSQL_ROOT_CMD="mariadb -u root -p${MYSQL_ROOT_PASSWORD} --connect-timeout=5"

    # --- Wait for local MariaDB to accept connections (up to 2 minutes) ---
    # Use root here: repl_admin is created by initdb which runs during this same startup.
    # Root is available as soon as the socket is up; repl_admin will exist shortly after.
    echo "[repl] Waiting for local MariaDB..."
    READY=0
    for i in $(seq 1 24); do
      if $MYSQL_ROOT_CMD -e "SELECT 1" >/dev/null 2>&1; then
        echo "[repl] MariaDB ready."
        READY=1
        break
      fi
      echo "[repl] Not ready yet, retrying in 5s... ($i/24)"
      sleep 5
    done

    if [ "$READY" -eq 0 ]; then
      echo "[repl] ERROR: MariaDB not ready after 120s. Giving up."
      exit 1   # only fatal exit — pod should restart if MariaDB never came up
    fi

    # --- Skip if REPL_HOST is not configured ---
    if [ -z "${REPL_HOST}" ]; then
      echo "[repl] REPL_HOST not set — skipping replication setup."
      exit 0
    fi

    # --- Idempotency: skip if slave is already running OR connecting ---
    # "Connecting" means CHANGE MASTER TO already ran but remote is temporarily unreachable.
    # MariaDB retries on its own — no need to reconfigure.
    SLAVE_IO_RUNNING=$($MYSQL_CMD -N -e "SHOW SLAVE STATUS\G" 2>/dev/null \
      | grep "Slave_IO_Running:" | awk '{print $2}')
    if [ "$SLAVE_IO_RUNNING" = "Yes" ] || [ "$SLAVE_IO_RUNNING" = "Connecting" ]; then
      echo "[repl] Replication already configured (Slave_IO_Running=${SLAVE_IO_RUNNING}). Nothing to do."
      exit 0
    fi

    # --- Configure and start replication ---
    REPL_PORT_ACTUAL="${REPL_PORT:-3306}"
    echo "[repl] Configuring replication → ${REPL_HOST}:${REPL_PORT_ACTUAL}"

    # Get master's current GTID position so we don't replay its history.
    # dbtwo may have its own GTID transactions from initdb (e.g. 0-2-6).
    # Applying master's older GTIDs (e.g. 0-1-1) on top would violate gtid_strict_mode.
    # Setting gtid_slave_pos to master's current pos tells MariaDB: start replicating from NOW.
    MASTER_GTID=$(mariadb -h"${REPL_HOST}" -P"${REPL_PORT_ACTUAL}" \
      -u replicator -p"${REPL_PASSWORD}" \
      --connect-timeout=10 -N -e "SELECT @@gtid_current_pos;" 2>/dev/null || echo "")

    if [ -z "$MASTER_GTID" ]; then
      echo "[repl] ERROR: Could not fetch master GTID position."
      echo "[repl] The 'replicator' user on ${REPL_HOST} likely lacks REPLICATION CLIENT privilege."
      echo "[repl] Run on master: GRANT REPLICATION CLIENT ON *.* TO 'replicator'@'%'; FLUSH PRIVILEGES;"
      echo "[repl] Then delete and recreate this pod to retry."
      echo "[repl] Skipping CHANGE MASTER TO to avoid GTID conflict — pod will stay Running."
      exit 0
    fi

    echo "[repl] Setting gtid_slave_pos to master's current position: ${MASTER_GTID}"
    # RESET MASTER clears dbtwo's own binlog (0-2-x from initdb transactions)
    # so SET GLOBAL gtid_slave_pos won't conflict with a more recent local GTID
    $MYSQL_ROOT_CMD -e "RESET MASTER; SET GLOBAL gtid_slave_pos='${MASTER_GTID}';"

    # --- Seed from master if it has existing data and local DB is empty ---
    # Check if master GTID sequence number > 0 (master has transactions beyond init)
    MASTER_SEQ=$(echo "$MASTER_GTID" | awk -F'-' '{print $3}')
    LOCAL_TABLES=$($MYSQL_ROOT_CMD -N -e \
      "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema NOT IN \
      ('mysql','information_schema','performance_schema','sys');" 2>/dev/null || echo "0")

    if [ "${MASTER_SEQ:-0}" -gt 0 ] && [ "${LOCAL_TABLES:-0}" -eq 0 ]; then
      echo "[repl] Master has data (GTID seq=${MASTER_SEQ}), local DB is empty — seeding from master..."
      mariadb-dump \
        -h"${REPL_HOST}" -P"${REPL_PORT_ACTUAL}" \
        -u replicator -p"${REPL_PASSWORD}" \
        --databases {{ .Values.config.k3sAppName }} \
        --single-transaction \
        --master-data=2 \
        --gtid \
        2>&1 | tee /tmp/seed_dump.sql | $MYSQL_ROOT_CMD
      DUMP_RC=${PIPESTATUS[0]}
      if [ "$DUMP_RC" -ne 0 ]; then
        echo "[repl] ERROR: mariadb-dump failed (exit ${DUMP_RC}). Check replicator user privileges on master."
        echo "[repl] Run on master: GRANT SELECT, RELOAD, LOCK TABLES ON *.* TO 'replicator'@'%'; FLUSH PRIVILEGES;"
        echo "[repl] Then rebuild this pod."
        rm -f /tmp/seed_dump.sql
        exit 0
      fi
      rm -f /tmp/seed_dump.sql
      echo "[repl] Seed complete. Updating gtid_slave_pos from dump..."
      NEW_GTID=$($MYSQL_ROOT_CMD -N -e "SELECT @@gtid_slave_pos;" 2>/dev/null || echo "")
      echo "[repl] gtid_slave_pos after seed: ${NEW_GTID}"
    else
      echo "[repl] No seed needed (master seq=${MASTER_SEQ:-0}, local tables=${LOCAL_TABLES:-0})."
    fi

    $MYSQL_CMD <<-EOSQL
      STOP SLAVE;
      CHANGE MASTER TO
        MASTER_HOST     = '${REPL_HOST}',
        MASTER_PORT     = ${REPL_PORT_ACTUAL},
        MASTER_USER     = 'replicator',
        MASTER_PASSWORD = '${REPL_PASSWORD}',
        MASTER_USE_GTID = slave_pos;
      START SLAVE;
    EOSQL

    echo "[repl] Done. Slave status (remote may still be unreachable — that is normal):"
    $MYSQL_CMD -e "SHOW SLAVE STATUS\G" 2>/dev/null \
      | grep -E "Slave_IO_Running|Slave_SQL_Running|Seconds_Behind_Master|Last_Error" || true

    exit 0
{{- end }}
{{- end }}