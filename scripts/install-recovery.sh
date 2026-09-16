# === G386F sshd reliability fix, added 2026-09-15 (see /sdcard/heal-pts.sh, README §6) ===
# Root cause chain: CPU suspend -> dropped adb/ssh sessions -> zombie shells ->
# poisoned /dev/pts -> dropbear pty setup failures (sessions die instantly or
# deliver mangled input to mksh). Wake lock stops the suspend-driven churn;
# oom_adj shields the sshd daemon and its children from lowmemorykiller.
(
	sleep 30
	echo sshd > /sys/power/wake_lock 2>/dev/null
	n=0
	while [ $n -lt 24 ]; do
		pid=$(cat /data/data/org.galexander.sshd/files/dropbear.pid 2>/dev/null)
		if [ -n "$pid" ] && [ -d /proc/$pid ]; then
			echo -17 > /proc/$pid/oom_adj 2>/dev/null
			break
		fi
		sleep 5
		n=$((n+1))
	done
) &
