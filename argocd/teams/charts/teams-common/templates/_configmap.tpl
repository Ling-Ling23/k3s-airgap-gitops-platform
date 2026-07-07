{{- define "team1-common.configmap" -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Values.config.k3sAppName }}-config
  namespace: {{ .Values.namespace }}
  labels:
    app: {{ .Values.config.k3sAppName | quote }}
    app.kubernetes.io/name: {{ .Values.config.k3sAppName | quote }}
    app.kubernetes.io/part-of: {{ index .Values.labels "part-of" }}
    app.kubernetes.io/managed-by: {{ index .Values.labels "managed-by" }}
    environment: {{ .Values.labels.environment }}
    team: {{ .Values.labels.team }}
data:
  APP_NAME: {{ .Values.config.appName | quote }}
  APP_IMAGE: {{ .Values.image.repository }}:{{ .Values.image.tag }}
  APP_VERSION: {{ .Chart.AppVersion | quote }}
  ADMINER_DIR: "/var/www/localhost/htdocs/{{ .Values.config.appName }}-adminer"
  CODIAD_DIR: "/var/www/localhost/htdocs/{{ .Values.config.appName }}-codiad"
  PROJECT_DIR: "/var/www/localhost/htdocs/{{ .Values.config.appName }}"
  PROJECT_GIT_URL: "ssh://git@$PRIVATE_GH_FQDN/infrateam-{{ .Values.config.appName }}.git"
  PROJECT_GIT_BRANCH: {{ .Values.config.projectGitBranch | quote }}
  PROJECT_NAME: {{ .Values.config.appName | quote }}
  WEBCONSOLE_DIR: "/var/www/html/{{ .Values.config.appName }}-console"
  CRON_OPTS: "-m {{ .Values.config.appName }}-cron@list..com"
  STACK: {{ .Values.config.appName | quote }}
  MYSQL_DATABASE: {{ .Values.config.appName | quote }}
{{- end }}
