{{- define "team1-common.database.replenv" -}}
{{- if .Values.database.enabled }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Values.config.k3sAppName }}-repl-env
  namespace: {{ .Values.namespace }}
  labels:
    app: {{ .Values.config.k3sAppName }}-database
data:
  # REPL_HOST / REPL_PORT — set these in your values file per-cluster:
  #
  # Option B — HAProxy on this cluster (recommended for HA):
  #   replHost: "haproxy.kube-system.svc.cluster.local"
  #   replPort: "3336"   # HAProxy frontend port pointing to remote NodePorts
  #
  # Option C — Same-cluster test only:
  #   replHost: "dbtwo-data-0.dbtwo-mariadb.team1.svc.cluster.local"
  #   replPort: "3306"
  #
  REPL_HOST: {{ .Values.database.replHost | quote }}
  REPL_PORT: {{ .Values.database.replPort | quote }}
{{- end }}
{{- end }}