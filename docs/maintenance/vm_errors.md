# ISSUE: ip6tables-restore v1.8.10 (nf_tables): unknown option "--xor-mark
tail -f   /var/log/syslog | grep -C 10 "ip6tables-restore"
## Fix : switch IPv6 iptables to legacy
iptables --version
ip6tables --version

sudo modprobe ip6table_mangle
sleep 3
sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
sleep 3
sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
-> ON WORKER NODE: sudo systemctl restart k3s-agent 
-> ON MASTER NODE: sudo systemctl restart k3s
Note: no need for dryout 

iptables --version
ip6tables --version

## Expected:
### iptables --version
iptables v1.8.10 (legacy)
### ip6tables --version
ip6tables v1.8.10 (legacy)

## will this survive VM reload?
sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
Yes — these should survive a VM reboot, because they update persistent symlinks.

sudo modprobe ip6table_mangle
Not guaranteed — this only loads the module for the current running kernel session. After reboot, it may load automatically, but do not rely on that.

To make the module persistent
Add it to a modules-load file, for example:

/etc/modules-load.d/ip6table_mangle.conf
with:

ip6table_mangle
If needed, also add:

xt_mark
Bottom line
update-alternatives: persistent
modprobe: temporary unless configured to load at boot
After a reboot, verify with:

ip6tables --version
lsmod | grep -E 'ip6table_mangle|xt_mark'
If wanted, a small persistent boot-safe fix snippet can be added to your notes.



## IT DIDNT WORK, NOW TRY:
Commands:

sudo tee /etc/sysctl.d/99-k3s-disable-ipv6.conf > /dev/null <<'EOF'
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
EOF
sudo sysctl --system
sudo systemctl restart k3s-agent (worker) or sudo systemctl restart k3s (server)
Then verify:

journalctl -u k3s -n 200 --no-pager | grep -E "xor-mark|Failed to execute iptables-restore|ipFamily=\"IPv6\""