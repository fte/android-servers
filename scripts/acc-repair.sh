#!/system/bin/sh
# acc-repair.sh - clean ACC half-installs and (re)install, detached from SSH
#
# Why: acc's install.sh ends with `service.sh --init`, whose accd inherits the
# SSH-owned stdout and keeps the session open for minutes; a killed session
# aborts the install mid-copy (and a re-run first rm -rf's the previous tree).
# This script redirects everything to files on /sdcard and polls for completion.
#
# Launch (returns immediately):
#   ssh -p 2222 user@phone 'su -c "sh /sdcard/acc-repair.sh > /sdcard/acc-repair.log 2>&1 &"'
# Watch progress:
#   ssh -p 2222 user@phone 'su -c "tail -5 /sdcard/acc-repair.log /sdcard/acc-install.log"'

BB=/system/xbin/busybox
LOG=/sdcard/acc-install.log

echo "=== acc-repair $(date) ==="

echo "--- 1. stop acc processes"
$BB pkill -f accd 2>/dev/null
sleep 1
$BB pkill -9 -f accd 2>/dev/null

echo "--- 2. wipe partial state"
rm -rf /data/adb/vr25/acc /data/adb/vr25/acc-data /dev/.vr25/acc /data/local/tmp/accx
if [ ! -x /data/adb/vr25/bin/busybox ]; then
	mkdir -p /data/adb/vr25/bin
	cp /sdcard/busybox /data/adb/vr25/bin/busybox
	chmod 0755 /data/adb/vr25/bin/busybox
fi
$BB sha256sum /sdcard/busybox /data/adb/vr25/bin/busybox

echo "--- 3. extract + run official installer (detached, log: $LOG)"
mkdir -p /data/local/tmp/accx
$BB tar -xzf /sdcard/acc.tgz -C /data/local/tmp/accx || { echo "REPAIR-FAIL: tar"; exit 1; }
cd /data/local/tmp/accx/acc_* || { echo "REPAIR-FAIL: cd"; exit 1; }
export installDir=/data/adb/vr25
/system/bin/sh ./install.sh > "$LOG" 2>&1 < /dev/null &
echo "installer pid $!"

echo "--- 4. wait for install + daemon (up to 8 min)"
n=0
while [ $n -lt 96 ]; do
	if [ -f /data/adb/vr25/acc/acc ] && /data/adb/vr25/acc/acc -D > /dev/null 2>&1; then
		echo "REPAIR-OK: acc installed, accd running"
		break
	fi
	sleep 5
	n=$((n + 1))
done

if [ ! -f /data/adb/vr25/acc/acc ]; then
	echo "REPAIR-FAIL: acc file missing after wait; installer log tail:"
	tail -20 "$LOG"
	exit 1
fi

if ! /data/adb/vr25/acc/acc -D > /dev/null 2>&1; then
	echo "--- 5. daemon not up yet - explicit init"
	test -f /dev/.vr25/acc/acca || \
		/system/bin/sh /data/adb/vr25/acc/service.sh > /dev/null 2>&1 < /dev/null &
	sleep 15
fi

echo "--- final state"
/data/adb/vr25/acc/acc -v 2>&1 | head -1
/data/adb/vr25/acc/acc -D 2>&1 | head -3
/data/adb/vr25/acc/acc -D > /dev/null 2>&1 && echo "REPAIR-OK-2: daemon confirmed" || echo "REPAIR-PARTIAL: files OK, daemon not confirmed (re-check in a minute)"
echo "=== acc-repair done $(date) ==="
