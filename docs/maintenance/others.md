# too many open files
find /proc/*/fd -lname 'anon_inode:inotify' 2>/dev/null | wc -l
max_user_instances is 128

sysctl fs.inotify.max_user_instances fs.inotify.max_user_watches fs.inotify.max_queued_events
OR
cat /proc/sys/fs/inotify/max_user_instances
cat /proc/sys/fs/inotify/max_user_watches
cat /proc/sys/fs/inotify/max_queued_events

FIX
tee /etc/sysctl.d/99-inotify.conf <<EOF
fs.inotify.max_user_instances=512
fs.inotify.max_user_watches=524288
fs.inotify.max_queued_events=16384
EOF

sysctl -p /etc/sysctl.d/99-inotify.conf