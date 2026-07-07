{{- define "team1-common.database.sts" -}}
{{- if .Values.database.enabled }}
apiVersion: apps/v1
kind: StatefulSet
metadata:
  annotations:
    argocd.argoproj.io/tracking-id: {{ .Values.config.k3sAppName }}-{{ .Values.labels.environment }}:apps/StatefulSet:team1/{{ .Values.config.k3sAppName }}-data
  labels:
    app: {{ .Values.config.k3sAppName }}-database
    app.kubernetes.io/name: {{ .Values.config.k3sAppName }}
    environment: {{ .Values.labels.environment }} # !
    team: {{ .Values.labels.team }}
  name: {{ .Values.config.k3sAppName }}-data
  namespace: {{ .Values.namespace }}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: {{ .Values.config.k3sAppName }}-data
  serviceName: {{ .Values.config.k3sAppName }}-mariadb
  template:
    metadata:
      labels:
        app: {{ .Values.config.k3sAppName }}-data
        app.kubernetes.io/name: {{ .Values.config.k3sAppName }}
        environment: {{ .Values.labels.environment }}
        team: {{ .Values.labels.team }}
    spec:
      containers:
        - env:
            - name: MYSQL_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  key: {{ .Values.config.k3sAppName }}
                  name: {{ .Values.database.vault_root_secret_name }}
            - name: MYSQL_DATABASE
              value: {{ .Values.config.k3sAppName }}
            # --- Replication env vars (both sourced from {{ .Values.database.vault_root_secret_name }}) ---
            - name: REPL_PASSWORD
              valueFrom:
                secretKeyRef:
                  key: repl_admin
                  name: {{ .Values.database.vault_root_secret_name }}
            - name: REPL_ADMIN_PASSWORD
              valueFrom:
                secretKeyRef:
                  key: repl_admin
                  name: {{ .Values.database.vault_root_secret_name }}
            - name: REPL_HOST
              valueFrom:
                configMapKeyRef:
                  key: REPL_HOST
                  name: {{ .Values.config.k3sAppName }}-repl-env
            - name: REPL_PORT
              valueFrom:
                configMapKeyRef:
                  key: REPL_PORT
                  name: {{ .Values.config.k3sAppName }}-repl-env
            # --- ProxySQL users (created on first DB init via initdb script) ---
            - name: PROXYSQL_MONITOR_PASSWORD
              valueFrom:
                secretKeyRef:
                  key: proxysql_monitor
                  name: {{ .Values.database.vault_root_secret_name }}
            - name: APP_USER
              value: {{ .Values.config.k3sAppName | replace "-" "_" }}_app
            - name: APP_USER_PASSWORD
              valueFrom:
                secretKeyRef:
                  key: {{ .Values.config.k3sAppName }}-app-password
                  name: {{ .Values.database.vault_root_secret_name }}
          image: $ARTIFACTORY/mariadb:11.8.5
          name: {{ .Values.config.k3sAppName }}-data
          ports:
            - containerPort: 3306
              name: mysql
              protocol: TCP
          resources:
            limits:
              cpu: '2'
              memory: 2G
            requests:
              cpu: '0.5'
              memory: 512Mi
          lifecycle:
            postStart:
              exec:
                command:
                  - /bin/bash
                  - /usr/local/bin/setup-replication.sh
          volumeMounts:
            - mountPath: /var/lib/mysql
              name: mariadb-data
            - mountPath: /etc/mysql/conf.d/replication.cnf
              name: replication-config
              subPath: replication.cnf
            # Init scripts: sourced by MariaDB entrypoint on first DB init
            - mountPath: /docker-entrypoint-initdb.d/01-create-replication-user.sh
              name: init-scripts
              subPath: 01-create-replication-user.sh
            # Setup script: called by postStart hook on every pod start
            - mountPath: /usr/local/bin/setup-replication.sh
              name: init-scripts
              subPath: setup-replication.sh
      hostname: {{ .Values.hostname }}
      initContainers:
        - command:
            - rm
            - '-rf'
            - /var/lib/mysql/lost+found
          image: >-
            $ARTIFACTORY/busybox:latest
          name: cleanup-lost-found
          resources:
            limits:
              cpu: 100m
              memory: 64Mi
            requests:
              cpu: 50m
              memory: 32Mi
          volumeMounts:
            - mountPath: /var/lib/mysql
              name: mariadb-data
        - command:
            - sh
            - '-c'
            - |
              mkdir -p /run/mysqld
              chown mysql:mysql /run/mysqld
              chmod 755 /run/mysqld
          image: $ARTIFACTORY/mariadb:11.8.5
          name: fix-mysqld-run-dir
          resources:
            limits:
              cpu: 100m
              memory: 64Mi
            requests:
              cpu: 50m
              memory: 32Mi
          securityContext:
            runAsUser: 0
          volumeMounts:
            - mountPath: /run/mysqld
              name: mariadb-run
      volumes:
        - emptyDir: {}
          name: mariadb-run
        - configMap:
            name: {{ .Values.config.k3sAppName }}-replication-config
          name: replication-config
        - configMap:
            name: {{ .Values.config.k3sAppName }}-init-scripts
            defaultMode: 0755
          name: init-scripts
  volumeClaimTemplates:
    - metadata:
        labels:
          app: {{ .Values.config.k3sAppName }}-database
        name: mariadb-data
      spec:
        accessModes:
          - ReadWriteOnce
        resources:
          requests:
            storage: 150Gi
        storageClassName: longhorn
{{- end }}
{{- end }}