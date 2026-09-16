#!/system/bin/sh
# sshd-diag.sh - capture sshd / pty state (run as root: sh /sdcard/sshd-diag.sh)
BB=busybox
echo "===DATE==="; date
echo "===PS-DROPBEAR==="
$BB ps w | $BB grep -i dropbear | $BB grep -v grep
echo "===PIDFILE==="
cat /data/data/org.galexander.sshd/files/dropbear.pid 2>/dev/null; echo
echo "===LISTEN-OWNERS==="
inodes=$($BB awk '$2 ~ /:08AE$/ && $4 == "0A" {print $10}' /proc/net/tcp /proc/net/tcp6 2>/dev/null)
echo "listen-inodes: $inodes"
for i in $inodes; do
  for p in /proc/[0-9]*; do
    pid=${p#/proc/}
    for fd in $p/fd/*; do
      case "$($BB readlink "$fd" 2>/dev/null)" in
        "socket:[$i]")
          echo "LISTEN owner pid=$pid cmd=$($BB tr '\000' ' ' < $p/cmdline 2>/dev/null)"
          break 2 ;;
      esac
    done
  done
done
echo "===PTY-ALLOC==="
$BB script -c 'tty' /dev/null
$BB script -c 'sleep 5; tty' /dev/null &
sleep 1
$BB script -c 'tty' /dev/null
echo "--pts listing during concurrent alloc--"
$BB ls -la /dev/pts
wait
echo "===DMESG-TTY==="
dmesg 2>/dev/null | $BB grep -iE "pty|tty|pts" | $BB tail -15
echo "===ERR-TAIL==="
tail -c 1500 /data/data/org.galexander.sshd/files/dropbear.err 2>/dev/null
