{{- define "team1-common.database.replcnf" -}}
{{- if .Values.database.enabled }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Values.config.k3sAppName }}-replication-config
  namespace: {{ .Values.namespace }}
  labels:
    app: {{ .Values.config.k3sAppName }}-database
data:
  replication.cnf: |
    [mysqld]
    # --- Identity ---
    server_id              = {{ .Values.database.replication.serverId }}
    gtid_domain_id         = {{ .Values.database.replication.gtidDomainId }}
    # --- Auto-increment offset (master-master conflict prevention) ---
    auto_increment_increment = 2
    auto_increment_offset    = {{ .Values.database.replication.autoIncrementOffset }}
    # --- Binary logging ---
    log_bin            = mysql-bin
    binlog_format      = ROW
    log_slave_updates  = ON
    expire_logs_days   = 14
    # --- GTID ---
    gtid_strict_mode   = ON
    # --- Relay log ---
    relay_log          = relay-bin
    relay_log_index    = relay-bin.index
    # --- Read-only: ON for standby, OFF for primary ---
    read_only          = {{ .Values.database.replication.readOnly }}
    # --- Performance / safety ---
    innodb_flush_log_at_trx_commit = 1
    sync_binlog                    = 1
{{- end }}
{{- end }}
