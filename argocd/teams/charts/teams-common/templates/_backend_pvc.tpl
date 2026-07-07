{{- define "team1-common.backend.pvc" -}}
{{- if .Values.backend.enabled }}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ .Values.config.k3sAppName }}-src-backend
  namespace: {{ .Values.namespace }}
  labels:
    app: {{ .Values.config.k3sAppName }}-backend
    app.kubernetes.io/name: {{ .Values.config.k3sAppName }}
    app.kubernetes.io/part-of: {{ index .Values.labels "part-of" }}
    app.kubernetes.io/managed-by: {{ index .Values.labels "managed-by" }}
    environment: {{ .Values.labels.environment }}
    team: {{ .Values.labels.team }}
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
  storageClassName: longhorn
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ .Values.config.k3sAppName }}-crontab-backend
  namespace: {{ .Values.namespace }}
  labels:
    app: {{ .Values.config.k3sAppName }}-backend
    app.kubernetes.io/name: {{ .Values.config.k3sAppName }}
    app.kubernetes.io/part-of: {{ index .Values.labels "part-of" }}
    app.kubernetes.io/managed-by: {{ index .Values.labels "managed-by" }}
    environment: {{ .Values.labels.environment }}
    team: {{ .Values.labels.team }}
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
  storageClassName: longhorn
{{- end }}
{{- end }}