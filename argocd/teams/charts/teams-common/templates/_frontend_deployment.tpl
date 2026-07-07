{{- define "team1-common.frontend.deployment" -}}
{{- if .Values.frontend.enabled }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Values.config.k3sAppName }}-frontend
  namespace: {{ .Values.namespace }}
  labels:
    app: {{ .Values.config.k3sAppName }}-frontend
    app.kubernetes.io/name: {{ .Values.config.k3sAppName | quote }}
    app.kubernetes.io/part-of: {{ index .Values.labels "part-of" }}
    app.kubernetes.io/managed-by: {{ index .Values.labels "managed-by" }}
    environment: {{ .Values.labels.environment }}
    team: {{ .Values.labels.team }}
spec:
  replicas: {{ .Values.replicaCount }}
  minReadySeconds: 20
  selector:
    matchLabels:
      app: {{ .Values.config.k3sAppName }}-frontend
  template:
    metadata:
      labels:
        app: {{ .Values.config.k3sAppName }}-frontend
        app.kubernetes.io/name: {{ .Values.config.k3sAppName | quote }}
        app.kubernetes.io/part-of: {{ index .Values.labels "part-of" }}
        app.kubernetes.io/managed-by: {{ index .Values.labels "managed-by" }}
        environment: {{ .Values.labels.environment }}
        team: {{ .Values.labels.team }}
    spec:
      hostname: {{ .Values.hostname }}
      initContainers:
        - name: fix-log-permissions
          image: $ARTIFACTORY/busybox:latest
          command: ["sh", "-c", "chmod 1777 /var/www/logs"]
          resources:
            requests:
              memory: "32Mi"
              cpu: "10m"
            limits:
              memory: "32Mi"
              cpu: "10m"
          volumeMounts:
            - name: python-logs
              mountPath: /var/www/logs
      containers:
        - name: {{ .Values.config.k3sAppName }}-frontend
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          lifecycle:
            postStart:
              exec:
                command: ["sh", "-c", "sed -i 's/develop_str=\"develop\"/develop_str=\"whatevermate\"/g' /usr/local/bin/create-project.sh"]
          ports:
            - containerPort: 80
              name: http
              protocol: TCP
            - containerPort: 22
              name: ssh
              protocol: TCP
          envFrom:
            - configMapRef:
                name: shared-app-config
            - configMapRef:
                name: {{ .Values.config.k3sAppName }}-config
          volumeMounts:
            - name: ssh-keys
              mountPath: /var/run/secrets
              readOnly: true
            - name: team1-certs
              mountPath: /opt/infrateam/certs
              readOnly: true
            - name: site-packages
              mountPath: /opt/site_packages
            - name: infrateam-libs
              mountPath: /opt/infrateam_libs
            - name: etc-ssl-certs
              mountPath: /etc/ssl/certs
              readOnly: true
            - name: ca-certificates
              mountPath: /usr/share/ca-certificates/
              readOnly: true
            - name: python-logs
              mountPath: /var/www/logs
            - name: crontab-frontend
              mountPath: /var/spool/cron/crontabs/
            - name: src-frontend
              mountPath: /var/www/src/team1FlaskApp
          resources:
            requests:
              memory: {{ .Values.resources.requests.memory | quote }}
              cpu: {{ .Values.resources.requests.cpu | quote }}
            limits:
              memory: {{ .Values.resources.limits.memory | quote }}
              cpu: {{ .Values.resources.limits.cpu | quote }}
      volumes:
        - name: ssh-keys
          secret:
            secretName: team1-shared-app-secrets
        - name: team1-certs
          secret:
            secretName: team1-certs
            items:
            - key: tls.key
              path: tls.key
            - key: tls.crt
              path: tls.crt
            - key: tls.crt
              path: ca.crt
            - key: infrateam.pem
              path: infrateam.pem
            - key: infrateam.pem
              path: infrateam.bundle-ca.pem
        - name: site-packages
          hostPath:
            path: /home/$TOOLING_ACCOUNT_ID/python3.6_virtual_env/lib/python3.6/site-packages
        - name: infrateam-libs
          hostPath:
            path: /home/$TOOLING_ACCOUNT_ID/hoho_scripts
        - name: etc-ssl-certs
          hostPath:
            path: /etc/ssl/certs
        - name: ca-certificates
          hostPath:
            path: /usr/share/ca-certificates/
        - name: python-logs
          hostPath:
            path: /opt/logs/pylogs/{{ .Values.config.k3sAppName }}/
            type: DirectoryOrCreate
        - name: crontab-frontend
          persistentVolumeClaim:
            claimName: {{ .Values.config.k3sAppName }}-crontab-frontend
        - name: src-frontend
          persistentVolumeClaim:
            claimName: {{ .Values.config.k3sAppName }}-src-frontend

{{- end }}
{{- end }}