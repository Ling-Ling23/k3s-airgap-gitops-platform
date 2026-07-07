{{- define "team1-common.git-sync-cronjob" -}}
{{- if (or .Values.backend.enabled .Values.frontend.enabled) }}
{{- if .Values.gitSync.enabled }}
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .Values.config.k3sAppName }}-git-sync
  namespace: {{ .Values.namespace }}
  labels:
    app: {{ .Values.config.k3sAppName }}-git-sync
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ .Values.config.k3sAppName }}-git-sync
  namespace: {{ .Values.namespace }}
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ .Values.config.k3sAppName }}-git-sync
  namespace: {{ .Values.namespace }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: {{ .Values.config.k3sAppName }}-git-sync
subjects:
  - kind: ServiceAccount
    name: {{ .Values.config.k3sAppName }}-git-sync
    namespace: {{ .Values.namespace }}
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {{ .Values.config.k3sAppName }}-git-sync
  namespace: {{ .Values.namespace }}
  labels:
    app: {{ .Values.config.k3sAppName }}-git-sync
spec:
  schedule: {{ .Values.gitSync.schedule | default "*/2 * * * *" | quote }}
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 2
  jobTemplate:
    spec:
      activeDeadlineSeconds: 60
      template:
        spec:
          serviceAccountName: {{ .Values.config.k3sAppName }}-git-sync
          restartPolicy: Never
          volumes:
            - name: ssh-keys
              secret:
                secretName: team1-shared-app-secrets
                defaultMode: 0400
          containers:
            - name: git-sync
              image: {{ .Values.image.repository }}:{{ .Values.image.tag }}
              command:
                - sh
                - -c
                - |
                  set -e
                  export GIT_SSH_COMMAND="ssh -i /var/run/secrets/id_rsa -o StrictHostKeyChecking=no"
                  NEW_SHA=$(git ls-remote {{ .Values.gitSync.repoURL }} refs/heads/{{ .Values.config.projectGitBranch }} | cut -f1)
                  if [ -z "$NEW_SHA" ]; then
                    echo "ERROR: could not resolve SHA from remote"
                    exit 1
                  fi
                  APISERVER="https://kubernetes.default.svc"
                  TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
                  CACERT="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
                  NS="{{ .Values.namespace }}"
                  DEPLOY_BACKEND="{{ .Values.config.k3sAppName }}-backend"
                  DEPLOY_FRONTEND="{{ .Values.config.k3sAppName }}-frontend"
                  CURRENT_SHA=$(curl -sf --cacert "$CACERT" \
                    -H "Authorization: Bearer $TOKEN" \
                    "$APISERVER/apis/apps/v1/namespaces/$NS/deployments/$DEPLOY_BACKEND" \
                    | grep -o '"src-revision":"[^"]*"' | cut -d'"' -f4 || echo "")
                  echo "Remote SHA : $NEW_SHA"
                  echo "Current SHA: $CURRENT_SHA"
                  if [ "$NEW_SHA" = "$CURRENT_SHA" ]; then
                    echo "No change, nothing to do."
                    exit 0
                  fi
                  echo "SHA changed — patching backend/frontend deployments to trigger rollout..."
                  PATCH="{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"src-revision\":\"$NEW_SHA\"}}}}}"

                  echo "Patching $DEPLOY_BACKEND (if present)"
                  curl -s --cacert "$CACERT" \
                    -H "Authorization: Bearer $TOKEN" \
                    -H "Content-Type: application/strategic-merge-patch+json" \
                    -X PATCH \
                    "$APISERVER/apis/apps/v1/namespaces/$NS/deployments/$DEPLOY_BACKEND" \
                    -d "$PATCH" >/dev/null || echo "Backend deployment not found; skipping"

                  echo "Patching $DEPLOY_FRONTEND (if present)"
                  curl -s --cacert "$CACERT" \
                    -H "Authorization: Bearer $TOKEN" \
                    -H "Content-Type: application/strategic-merge-patch+json" \
                    -X PATCH \
                    "$APISERVER/apis/apps/v1/namespaces/$NS/deployments/$DEPLOY_FRONTEND" \
                    -d "$PATCH" >/dev/null || echo "Frontend deployment not found; skipping"
                  echo "Done."
              volumeMounts:
                - name: ssh-keys
                  mountPath: /var/run/secrets
                  readOnly: true
              resources:
                requests:
                  cpu: "10m"
                  memory: "64Mi"
                limits:
                  cpu: "100m"
                  memory: "128Mi"
{{- end }}
{{- end }}
{{- end }}
