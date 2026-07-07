{{- define "team1-common.database.svc.headless" -}}
{{- if .Values.database.enabled }}
apiVersion: v1
kind: Service
metadata:
  annotations:
    argocd.argoproj.io/tracking-id: dbone-dev:/Service:team1/dbone-mariadb
  labels:
    app: {{ .Values.config.k3sAppName }}-database
  name: {{ .Values.config.k3sAppName }}-mariadb
  namespace: {{ .Values.namespace }}
spec:
  clusterIP: None
  ports:
    - name: mysql
      port: 3306
      protocol: TCP
      targetPort: 3306
  selector:
    app: {{ .Values.config.k3sAppName }}-data
{{- end }}
{{- end }}