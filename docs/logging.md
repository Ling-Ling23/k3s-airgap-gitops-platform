# hoho logs validate 
## tcpdump -i any udp port 514 -nn
tcpdump: data link type LINUX_SLL2
tcpdump: verbose output suppressed, use -v[v]... for full protocol decode
listening on any, link-type LINUX_SLL2 (Linux cooked v2), snapshot length 262144 bytes


systemctl restart rsyslog     
tail -f /opt/logs/pylogs/py3-bgtmohoho.log
journalctl -u rsyslog -n 50 -f

# APP ARMOR ISSUE
dmesg | grep -i apparmor | grep rsyslog
## Edit the rsyslog AppArmor profile
vi /etc/apparmor.d/usr.sbin.rsyslogd
## Add this line inside the profile block:
/opt/logs/pylogs/** rw,
## Reload the profile
apparmor_parser -r /etc/apparmor.d/usr.sbin.rsyslogd
systemctl restart rsyslog


# LOKI UNSYNC
The error segments are not sequential is Loki ingester WAL corruption/inconsistency.
Your Loki is Deployment with replicas: 3 and all replicas mount the same RWX PVC loki-data, so all ingesters share one filesystem path (loki.yaml, loki-pvc.yaml, loki-configmap.yaml).
After yesterday’s containerd cleanup/restarts, shared WAL/index state likely became inconsistent.
Immediate recovery (safe-first)

## didn't work :D
kubectl -n logging scale deploy/loki --replicas=0
kubectl -n logging run loki-repair --image=$ARTIFACTORY/busybox:latest --restart=Never --overrides='{"spec":{"containers":[{"name":"repair","image":"$ARTIFACTORY/busybox:latest","command":["sh","-c","sleep 3600"],"volumeMounts":[{"name":"d","mountPath":"/mnt"}]}],"volumes":[{"name":"d","persistentVolumeClaim":{"claimName":"loki-data"}}]}}'
kubectl -n logging exec -it pod/loki-repair -- sh
Inside pod: ls -la /mnt ; rm -rf /mnt/wal /mnt/index /mnt/cache
Exit + cleanup: kubectl -n logging delete pod/loki-repair
kubectl -n logging scale deploy/loki --replicas=1
Verify: kubectl -n logging get pods -w ; kubectl -n logging logs deploy/loki --tail=200


## worked
kubectl -n logging scale deploy/loki --replicas=0
kubectl -n logging run loki-repair --image=$ARTIFACTORY/busybox:latest --restart=Never --overrides='{"spec":{"containers":[{"name":"repair","image":"$ARTIFACTORY/busybox:latest","command":["sh","-c","sleep 3600"],"volumeMounts":[{"name":"d","mountPath":"/mnt"}]}],"volumes":[{"name":"d","persistentVolumeClaim":{"claimName":"loki-data"}}]}}'
kubectl -n logging exec -it pod/loki-repair -- sh -c 'find /mnt -mindepth 1 -maxdepth 1 -exec rm -rf {} + ; ls -la /mnt'
kubectl -n logging delete pod loki-repair
Sync ArgoCD app for logging so new chart values apply, then: kubectl -n logging rollout restart deploy/loki
kubectl -n logging get pods -w ; kubectl -n logging logs deploy/loki --tail=200


# NEW ALLOY CFG - NEEDS RESTART DAEMONSETS
kubectl rollout restart daemonset/alloy -n logging