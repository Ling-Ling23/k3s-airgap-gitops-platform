{{- define "team1-common.backend.service" -}}
{{- if .Values.backend.enabled }}
apiVersion: v1
kind: Service
metadata:
  name: {{ .Values.config.k3sAppName }}-backend
  namespace: {{ .Values.namespace }}
  labels:
    app: {{ .Values.config.k3sAppName }}-backend
    app.kubernetes.io/name: {{ .Values.config.k3sAppName }}
    app.kubernetes.io/part-of: {{ index .Values.labels "part-of" }}
    app.kubernetes.io/managed-by: {{ index .Values.labels "managed-by" }}
    environment: {{ .Values.labels.environment }}
    team: {{ .Values.labels.team }}
spec:
  type: ClusterIP
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
      name: http
    - port: 22
      targetPort: 22
      protocol: TCP
      name: ssh
  selector:
    app: {{ .Values.config.k3sAppName }}-backend
{{- end }}
{{- end }}
