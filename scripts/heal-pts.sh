#!/system/bin/sh
# heal-pts.sh v3 - devpts/tty heal for the G386F WITHOUT killing anything.
# Key trick: lazy umount detaches the poisoned devpts instance; live holders
# (zombie shells etc.) keep their fds on the detached instance and become
# harmless, while /dev/ptmx re-binds to the fresh instance mounted after.
LOG=/data/local/tmp/heal.log
BB=busybox
{
echo "=== heal start $(date) ==="

# 1. Protect sshd daemon + children from lowmemorykiller
pid=$(cat /data/data/org.galexander.sshd/files/dropbear.pid 2>/dev/null)
if [ -n "$pid" ] && [ -d /proc/$pid ]; then
	echo -17 > /proc/$pid/oom_adj 2>/dev/null && echo "oom_adj=-17 on dropbear pid $pid"
fi

# 2. wake lock: prevents CPU suspend -> no dropped adb/ssh sessions -> no zombies
echo sshd > /sys/power/wake_lock 2>/dev/null && echo "wake_lock applied"

# 3. Detach the poisoned devpts instance (lazy: holders unaffected) and mount fresh
echo "=== pts before ==="; $BB ls -la /dev/pts
$BB umount -l /dev/pts && echo LAZY-UMOUNT-OK || echo LAZY-UMOUNT-FAIL
$BB mount -t devpts -o mode=600 devpts /dev/pts && echo MOUNT-OK || echo MOUNT-FAIL
echo "=== pts after (must be empty) ==="; $BB ls -la /dev/pts
echo "=== mounts line ==="; $BB grep devpts /proc/mounts

echo "=== heal done $(date) ==="
} > $LOG 2>&1
cat $LOG
