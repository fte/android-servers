#!/system/bin/sh
# space-clean.sh - reclaim disk space on old Android (4.x, root required)
#
# Companion to debloat-422.sh: this one targets junk (logs, caches,
# crash dumps, thumbnails) instead of apps.
#
# Usage (adb shell, then `su`):
#   sh /sdcard/space-clean.sh report   # sizes only, deletes nothing
#   sh /sdcard/space-clean.sh clean    # wipe caches + logs (safe junk)
#   sh /sdcard/space-clean.sh deep     # also wipe dalvik-cache (rebuilds on reboot)
#
# Never put these here (system-critical data, not junk):
#   /data/system, /data/property, /data/misc, /data/app*,
#   /data/media (that IS your internal sdcard on many devices), /data/dalvik-cache
#   except in 'deep' mode, /data/data except app cache subdirs.

mode="${1:-report}"

# ---- dirs whose CONTENTS are junk (dir itself is kept) ----
TARGETS="
/cache
/data/system/dropbox
/data/anr
/data/tombstones
/data/dontpanic
/data/panic
/data/log
/data/local/tmp
/data/lost+found
/sdcard/DCIM/.thumbnails
/sdcard/DCIM/Camera/.thumbnails
"
# ---- app cache dirs, globbed at runtime ----
GLOBS="
/data/data/*/cache
/data/media/0/DCIM/.thumbnails
/sdcard/Android/data/*/cache
/sdcard/Android/obb/*/cache
"

# size of a dir in KB blocks; toolbox du lacks -sk sometimes -> busybox fallback
dirsize() {
	out=$(busybox du -sk "$1" 2>/dev/null) || out=$(du -sk "$1" 2>/dev/null) || out=
	case "$out" in
	''|*[!0-9\ \t/]*) ;;
	esac
	set -- $out
	case "$1" in ''|*[!0-9]*) echo 0 ;; *) echo "$1" ;; esac
}

# KB -> human readable
fmtkb() {
	kb=$1
	case "$kb" in ''|*[!0-9]*) kb=0 ;; esac
	if [ "$kb" -ge 1048576 ]; then
		echo "$((kb/1048576)).$(( (kb%1048576)*10/1048576 )) GB"
	elif [ "$kb" -ge 1024 ]; then
		echo "$((kb/1024)).$(( (kb%1024)*10/1024 )) MB"
	else
		echo "${kb} KB"
	fi
}

clean_contents() {
	[ -d "$1" ] || return 0
	if busybox find "$1" -mindepth 1 -maxdepth 1 -delete 2>/dev/null; then
		return 0
	fi
	rm -rf "$1"/* "$1"/.[!.]* "$1"/..?* 2>/dev/null
	return 0
}

expand_targets() {
	for p in $TARGETS; do
		[ -e "$p" ] && echo "$p"
	done
	for g in $GLOBS; do
		for p in $g; do
			[ -d "$p" ] && echo "$p"
		done
	done
}

df_summary() {
	echo "--- df ---"
	df -h 2>/dev/null || df
}

case "$mode" in
report)
	total=0
	echo "size       dir"
	echo "---------  ------------------------------------------"
	for p in $(expand_targets); do
		kb=$(dirsize "$p")
		total=$((total+kb))
		echo "$(fmtkb "$kb")  $p"
	done
	echo "---------"
	echo "safe-to-clean total: $(fmtkb "$total")"
	df_summary
	;;

clean)
	total=0
	for p in $(expand_targets); do
		kb=$(dirsize "$p")
		if [ "$kb" -gt 0 ]; then
			echo "cleaning $(fmtkb "$kb")  $p"
		fi
		clean_contents "$p"
		total=$((total+kb))
	done
	echo "freed approx: $(fmtkb "$total") (some is rebuilt as apps run)"
	df_summary
	echo "tip: storage the system reclaims lazily - reboot or re-check later."
	;;

deep)
	echo "deep mode: wiping dalvik-cache. First boot will be SLOW"
	echo "while the VM re-compiles every app. Space gain is mostly"
	echo "temporary UNLESS old stale entries exist (uninstalled apps)."
	printf "continue? [y/N] "
	read answer
	case "$answer" in
	y*|Y*)
		kb=$(dirsize /data/dalvik-cache)
		clean_contents /data/dalvik-cache
		echo "freed approx: $(fmtkb "$kb") - REBOOT NOW."
		;;
	*) echo "aborted." ;;
	esac
	;;

*)
	echo "unknown mode: $mode (use: report | clean | deep)"
	exit 1
	;;
esac
