#!/system/bin/sh
# ssh-doctor.sh — self-service diagnostic for SimpleSSHD on the SM-G386F.
#
# Run it from your Mac (works even when sshd is half-broken, as long as
# non-pty commands still pass — they do even in the poisoned state):
#
#     ssh g386f 'sh /sdcard/ssh-doctor.sh'
#
# Or plug the USB cable and run as root (full checks + repair executors):
#
#     adb shell "su -c 'sh /sdcard/ssh-doctor.sh --fix'"      # restart daemon
#     adb shell "su -c 'sh /sdcard/ssh-doctor.sh --nuclear'"  # + devpts heal
#
# NOTE: do NOT add `su` self-elevation inside this script. The old
# Chainfire su on this phone does not support quoted arguments (it splits
# on spaces) and nested `su -c "sh $0"` segfaults/hangs.

H=/data/data/org.galexander.sshd
ERR=$H/files/dropbear.err
ROOT=0
[ "$(busybox id -u 2>/dev/null)" = "0" ] && ROOT=1

sec() { echo; echo "== $1 =="; }

# Track our own session's pts so we never flag ourselves as the stale holder
MINE=none
for f in /proc/self/fd/*; do
  t=$(busybox readlink "$f" 2>/dev/null)
  case "$t" in /dev/pts/*) MINE=$t;; esac
done
echo "run as uid $(busybox id -u); my session pts: $MINE"

sec "1. dropbear daemon"
busybox netstat -tlnp 2>/dev/null | busybox grep 2222 \
  && echo "-> daemon ALIVE" \
  || echo "-> NOT LISTENING on 2222: open the SimpleSSHD app, or plug USB and run: adb shell \"su -c 'am startservice -n org.galexander.sshd/.SimpleSSHDService'\""

sec "2. last server errors (the important part)"
busybox tail -n 15 "$ERR" 2>/dev/null || echo "(no log)"
echo "-- decode:"
echo "   TIOCSCTTY 'Operation not permitted' alone = BENIGN noise"
echo "   '/dev/pts/N: No such file or directory'   = POISONED devpts -> --nuclear"
echo "   'no authorized keys'                      = key file gone  -> re-push key"

sec "3. pty state"
busybox ls -la /dev/pts 2>/dev/null
stale=0
for n in /dev/pts/[0-9]*; do
  [ -e "$n" ] || continue
  [ "$n" = "$MINE" ] && continue
  own=$(busybox ls -ld "$n" 2>/dev/null | busybox awk '{print $3":"$4}')
  echo "holder: $n ($own)"
  case "$own" in
    shell:shell) stale=1; echo "   ^ STALE adb/su leftover -> this is the '(' syntax error maker";;
  esac
done
[ "$stale" = 1 ] && echo "-> POISONED: fix with:  adb shell \"su -c 'sh /sdcard/ssh-doctor.sh --nuclear'\""

sec "4. protections"
if [ "$ROOT" = 1 ]; then
  if busybox grep -q sshd /sys/power/wake_lock 2>/dev/null; then
    echo "-> wake lock OK"
  else
    echo "-> wake lock MISSING: echo sshd > /sys/power/wake_lock"
  fi
  for p in /proc/[0-9]*; do
    c=$(busybox tr -d '\000' < "$p/cmdline" 2>/dev/null)
    case "$c" in *dropbear*|*galexander*) echo "daemon pid ${p#/proc/} oom_adj=$(cat "$p/oom_adj" 2>/dev/null) (want -17)";;
    esac
  done
else
  echo "(wake lock / oom_adj checks need root — run once via adb to verify)"
fi
if busybox grep -q heal-pts /system/etc/install-recovery.sh 2>/dev/null; then
  echo "-> boot hook OK (survives reboot)"
else
  echo "-> boot hook MISSING (fix won't survive reboot)"
fi

sec "5. your authorized key"
busybox ls -la $H/files/authorized_keys 2>/dev/null \
  || echo "MISSING: $H/files/authorized_keys (must be directly in files/, NOT files/.ssh/)"

# ---------------- repair executors (root / adb only) ----------------
case "$1" in
--fix)
  sec "FIX: restart SimpleSSHD"
  if [ "$ROOT" = 0 ]; then
    echo "needs root. Plug USB and run:"
    echo "  adb shell \"su -c 'am force-stop org.galexander.sshd; sleep 1; am startservice -n org.galexander.sshd/.SimpleSSHDService'\""
    exit 0
  fi
  am force-stop org.galexander.sshd
  sleep 1
  am startservice -n org.galexander.sshd/.SimpleSSHDService
  sleep 2
  busybox netstat -tln 2>/dev/null | busybox grep -q 2222 \
    && echo "FIX OK: listening again" || echo "FIX FAILED: reboot the phone"
  ;;
--nuclear)
  sec "NUCLEAR: devpts heal + restart"
  if [ "$ROOT" = 0 ]; then
    echo "needs root. Plug USB and run:"
    echo "  adb shell \"su -c 'sh /sdcard/heal-pts.sh; am force-stop org.galexander.sshd; sleep 1; am startservice -n org.galexander.sshd/.SimpleSSHDService'\""
    exit 0
  fi
  sh /sdcard/heal-pts.sh
  am force-stop org.galexander.sshd
  sleep 1
  am startservice -n org.galexander.sshd/.SimpleSSHDService
  sleep 2
  echo "pts now:"; busybox ls -la /dev/pts
  busybox netstat -tln 2>/dev/null | busybox grep -q 2222 \
    && echo "NUCLEAR OK" || echo "NUCLEAR FAILED: reboot the phone"
  ;;
esac

exit 0
