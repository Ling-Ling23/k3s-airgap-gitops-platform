{{- define "team1-common.database.svc.nodeport" -}}
{{- if .Values.database.enabled }}
apiVersion: v1
kind: Service
metadata:
  labels:
    app: {{ .Values.config.k3sAppName }}-database
  name: {{ .Values.config.k3sAppName }}-mariadb-nodeport
  namespace: {{ .Values.namespace }}
spec:
  type: NodePort
  ports:
    - name: mysql
      port: 3306
      protocol: TCP
      targetPort: 3306
      nodePort: {{ .Values.database.nodePort }}   # change if 30336 is already in use (range: 30000-32767)
  selector:
    app: {{ .Values.config.k3sAppName }}-data
{{- end }}
{{- end }}