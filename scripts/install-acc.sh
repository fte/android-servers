#!/system/bin/sh
# install-acc.sh - ACC (Advanced Charging Controller) installer for the SM-G386F
#
# Target: Samsung Galaxy Core LTE SM-G386F, Android 4.2.2 (Jelly Bean), rooted
# with SuperSU (README section 1). No custom recovery, no Magisk - so ACC is
# installed from its official release tarball into /data/adb/vr25/ (the
# "other root solutions" parent dir) and started from the
# /system/etc/install-recovery.sh boot hook (same pattern as the sshd fix).
#
# Pinned components (SHA256-verified):
#   acc      v2023.10.16   https://github.com/VR-25/acc/releases
#   busybox  1.36.1 armv7  https://github.com/Magisk-Modules-Repo/busybox-ndk
#                          (release 13614, file busybox-arm, static, non-selinux
#                          - right for the permissive-SELinux era of 4.2.2)
#
# Usage - on the PC (from the repo root; this script lives in scripts/):
#   sh scripts/install-acc.sh download                 # (re)fetch payload/acc.tgz + payload/busybox, verify hashes
#   sh scripts/install-acc.sh push user@192.168.1.20   # scp payload + script over SSH, then run the device install
#
# Usage - on the phone (SSH port 2222 or adb shell):
#   su -c 'sh /sdcard/install-acc.sh run'        # install / upgrade
#   su -c 'sh /sdcard/install-acc.sh status'     # daemon + battery + config summary
#   su -c 'sh /sdcard/install-acc.sh online'     # net install (needs busybox already in place)
#   su -c 'sh /sdcard/install-acc.sh uninstall'  # full removal (acc + boot hook block + busybox)
#
# After a successful install, follow acc-switch-procedure.md to find the
# charging switch with `acc -t p`, then set your thresholds (`acc 75 70`).

ACC_VER=v2023.10.16
ACC_URL="https://github.com/VR-25/acc/releases/download/$ACC_VER/acc_${ACC_VER}_202310160.tgz"
BB_URL="https://github.com/Magisk-Modules-Repo/busybox-ndk/releases/download/13614/UPDATE-Busybox.Installer.v1.36.1-ALL-signed.zip"

ACC_SHA256=115530c2ed8bac02bd78a48fae06a785722a2bc7d7ebbdd5ba00105412afa965
BB_SHA256=66436dc1e97d22886ed2d35bd69a9cb82bb0fdba4e4267c5184cee1d39a2f5f4

# acc commands: /dev/.vr25/acc/* links only exist after the boot-time init run
# (created by accd.sh --init); fall back to invoking acc.sh directly.
acc_cmd() {
	if [ -e /dev/.vr25/acc/acc ]; then
		/dev/.vr25/acc/acc "$@"
	else
		/system/bin/sh /data/adb/vr25/acc/acc.sh "$@"
	fi
}

# Device-side paths (files land flat in /sdcard via scp, as the device
# commands below and the README expect).
ACC_TGZ=/sdcard/acc.tgz
BB_SRC=/sdcard/busybox

# PC-side paths: this script sits in scripts/, the binaries it ships in payload/.
ROOT=$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)
[ -n "$ROOT" ] || ROOT=.
PAYLOAD=$ROOT/payload
SELF=$ROOT/scripts/install-acc.sh
BIN_DIR=/data/adb/vr25/bin
HOOK=/system/etc/install-recovery.sh
ACC=/data/adb/vr25/acc/acc
BB=$BIN_DIR/busybox

die() { echo "ERROR: $*" >&2; exit 1; }

# JB mksh creates temp files in /sqlite_stmt_journals, which does not exist on
# this ROM -> heredocs and case-patterns silently fail (empty file written!)
export TMPDIR=/data/local/tmp
test -d "$TMPDIR" || export TMPDIR=/data/adb/vr25/bin

# JB toolbox id ignores -u and prints the full line, so match on uid=0
root_check() {
	case "$(id 2>/dev/null)" in
	*'uid=0'*) : ;;
	*) die "not root - run: su -c 'sh /sdcard/install-acc.sh $1'" ;;
	esac
}

# ---------------------------------------------------------------- device side

remount_rw() {
	mount -o remount,rw /system 2>/dev/null ||
		mount -o remount,rw /system /system 2>/dev/null || return 1
	touch /system/.acc-rw-test 2>/dev/null || return 1
	rm -f /system/.acc-rw-test
	return 0
}

install_busybox() {
	mkdir -p "$BIN_DIR" || die "cannot create $BIN_DIR"
	if "$BB" echo -n "" >/dev/null 2>&1; then
		if printf '%s  %s\n' "$BB_SHA256" "$BB" | "$BB" sha256sum -c - >/dev/null 2>&1; then
			echo "busybox already in place (SHA256 OK): $BB"
			return 0
		fi
		echo "WARNING: $BB is corrupt/mismatched - trying to replace"
	fi
	cp "$BB_SRC" "$BB" || die "cp $BB_SRC failed (Text file busy? run: pkill -f accd)"
	chmod 0755 "$BB"
	"$BB" echo -n "" >/dev/null 2>&1 || die "$BB is not executable on this device"
	printf '%s  %s\n' "$BB_SHA256" "$BB" | "$BB" sha256sum -c - >/dev/null 2>&1 ||
		die "busybox SHA256 mismatch - re-download (sh install-acc.sh download)"
	echo "busybox installed: $BB"
}

install_acc() {
	printf '%s  %s\n' "$ACC_SHA256" "$ACC_TGZ" | "$BB" sha256sum -c - >/dev/null 2>&1 ||
		die "acc.tgz SHA256 mismatch - re-download (sh install-acc.sh download)"
	TMP=/data/local/tmp/accx # NOT acc_*: acc's uninstall.sh rm -rf's /data/local/tmp/acc[-_]*
	rm -rf "$TMP"
	mkdir -p "$TMP" || die "cannot create $TMP"
	"$BB" tar -xzf "$ACC_TGZ" -C "$TMP" || die "tar extraction failed"
	cd "$TMP"/acc_* || die "extracted acc directory not found"
	export installDir=/data/adb/vr25
	/system/bin/sh ./install.sh || die "install.sh failed - see $TMP (kept for inspection)"
	cd /
	rm -rf "$TMP"
	[ -f /data/adb/vr25/acc/acc.sh ] || die "install.sh finished but acc.sh is missing"
	echo "ACC installed in /data/adb/vr25/acc/"
}

patch_boot_hook() {
	if "$BB" grep -q 'vr25/acc/service.sh' "$HOOK" 2>/dev/null; then
		echo "boot hook: already patched"
		return 0
	fi
	cp -p "$HOOK" /sdcard/install-recovery.sh.bak.acc ||
		die "cannot backup $HOOK to /sdcard (skipping system edit)"
	remount_rw || die "cannot remount /system read-write"
	{
		echo ""
		echo "# === ACC autostart (added by install-acc.sh) ==="
		echo "( sleep 60"
		echo "  test -f /dev/.vr25/acc/acca || /system/bin/sh /data/adb/vr25/acc/service.sh"
		echo ") &"
	} >> "$HOOK" || die "cannot append to $HOOK"
	mount -o remount,ro /system 2>/dev/null
	echo "boot hook: ACC autostart added (backup: /sdcard/install-recovery.sh.bak.acc)"
}

# G386F/4.2.2: stock service.sh waits on `getprop sys.boot_completed`, but this
# ROM's toolbox getprop prints NOTHING for every property -> infinite wait, init
# never completes (no /dev/.vr25/acc/* links, no daemon). Fallback: /sdcard/Android
# exists once user storage is up; loop also capped at 5 min as a failsafe.
getprop_broken() {
	[ -z "$(/system/bin/getprop ro.build.version.release 2>/dev/null)" ]
}

fix_service_sh() {
	if ! getprop_broken; then
		echo "getprop works - service.sh left stock"
		return 0
	fi
	cat > /data/adb/vr25/acc/service.sh << 'G386FEOF'
#!/system/bin/sh
# acc initializer - G386F/Android 4.2.2 PATCH of VR-25/acc install/service.sh
# Stock boot-wait uses getprop sys.boot_completed; on this ROM toolbox getprop
# always prints empty, so the stock loop never exits. /sdcard/Android appears
# once user storage is mounted (boot done); loop capped as failsafe.
id=acc
domain=vr25
TMPDIR=/dev/.$domain/$id
execDir=/data/adb/$domain/$id
dataDir=/data/adb/$domain/${id}-data

[ -f $execDir/disable ] && exit 14

n=0
until { /system/bin/getprop sys.boot_completed 2>/dev/null | grep -q .; } || \
		[ -d /sdcard/Android ] || [ $n -ge 30 ]; do
	sleep 10
	n=$((n + 1))
done

mkdir -p $TMPDIR
export dataDir domain execDir id TMPDIR
. $execDir/setup-busybox.sh
. $execDir/release-lock.sh
exec start-stop-daemon -bx $execDir/${id}d.sh -S -- "$@" || exit 12
G386FEOF
	chmod 0755 /data/adb/vr25/acc/service.sh
	[ "$(wc -c < /data/adb/vr25/acc/service.sh)" -gt 400 ] ||
		die "service.sh patch failed to write (mksh temp file issue)"
	echo "service.sh patched for broken getprop (4.2.2 toolbox)"
}

init_and_verify() {
	# detached: service.sh daemonizes accd and would otherwise hold the SSH session open
	test -f /dev/.vr25/acc/acca || \
		/system/bin/sh /data/adb/vr25/acc/service.sh >/dev/null 2>&1 </dev/null &
	n=0
	while [ $n -lt 15 ]; do
		if acc_cmd -D >/dev/null 2>&1; then
			echo "accd: running"
			break
		fi
		sleep 2
		n=$((n + 1))
	done
	acc_cmd -D >/dev/null 2>&1 || echo "WARNING: accd not running yet - check acc -T"
	echo ""
	echo "== Next steps =="
	echo "  $ACC -t p      # find + persist a working charging switch (see acc-switch-procedure.md)"
	echo "  $ACC 75 70     # pause charging at 75%, resume at 70%"
	echo "  $ACC -T        # watch the daemon log"
	echo "If charging ever seems stuck: $ACC -e, replug the charger, or reboot."
}

do_run() {
	root_check run
	[ -f "$ACC_TGZ" ] || die "missing $ACC_TGZ - from the PC: sh install-acc.sh push user@phone"
	[ -f "$BB_SRC" ] || die "missing $BB_SRC - from the PC: sh install-acc.sh push user@phone"
	install_busybox
	install_acc
	fix_service_sh
	patch_boot_hook
	init_and_verify
}

	do_status() {
	root_check status
	[ -f /data/adb/vr25/acc/acc.sh ] || die "ACC not installed - run: su -c 'sh /sdcard/install-acc.sh run'"
	acc_cmd -D
	acc_cmd -i | sed -n '1,12p'
	echo "--- config (charging-relevant) ---"
	acc_cmd -s | "$BB" grep -E 'chargingSwitch|^capacity|pause|resume' || acc_cmd -s
}

do_online() {
	root_check online
	[ -x "$BB" ] || die "no busybox at $BB - use push mode instead"
	export PATH="$BIN_DIR:$PATH"
	"$BB" wget -O /data/local/tmp/install-online.sh \
		https://raw.githubusercontent.com/VR-25/acc/master/install-online.sh ||
		die "download failed (old busybox TLS?) - use push mode instead"
	/system/bin/sh /data/local/tmp/install-online.sh /data/adb/vr25
}

	do_fix_init() {
	root_check fix-init
	[ -d /data/adb/vr25/acc ] || die "ACC not installed - run: su -c 'sh /sdcard/install-acc.sh run'"
	fix_service_sh
	patch_boot_hook
	init_and_verify
}

do_uninstall() {
	root_check uninstall
	if [ -f /data/adb/vr25/acc/acc.sh ]; then
		acc_cmd -U || { rm -rf /data/adb/vr25/acc /data/adb/vr25/acc-data; echo "acc dirs removed manually"; }
	else
		rm -rf /data/adb/vr25/acc /data/adb/vr25/acc-data
	fi
	if [ -f "$HOOK" ] && "$BB" grep -q '=== ACC autostart' "$HOOK" 2>/dev/null; then
		remount_rw || die "cannot remount /system read-write"
		"$BB" sed -i '/=== ACC autostart/,/^) \&$/d' "$HOOK"
		mount -o remount,ro /system 2>/dev/null
		echo "boot hook: ACC block removed"
	fi
	rm -f "$BB"
	rmdir "$BIN_DIR" 2>/dev/null
	echo "uninstall done (busybox + hook block + acc removed). Verify charging works."
}

# ------------------------------------------------------------------- PC side

pc_download() {
	command -v curl >/dev/null || die "curl required"
	command -v unzip >/dev/null || die "unzip required"
	mkdir -p "$PAYLOAD" || die "cannot create $PAYLOAD"
	tmp=$(mktemp -d) || die "mktemp failed"
	curl -fsSL -o "$tmp/acc.tgz" "$ACC_URL" || die "acc download failed"
	curl -fsSL -o "$tmp/bb.zip" "$BB_URL" || die "busybox download failed"
	unzip -o "$tmp/bb.zip" busybox-arm -d "$tmp" >/dev/null || die "unzip failed"
	mv "$tmp/acc.tgz" "$PAYLOAD/acc.tgz" || die "cannot write $PAYLOAD/acc.tgz"
	mv "$tmp/busybox-arm" "$PAYLOAD/busybox" || die "cannot write $PAYLOAD/busybox"
	chmod 755 "$PAYLOAD/busybox"
	# relative names: sums stays valid if the repo moves
	printf '%s  %s\n' "$ACC_SHA256" acc.tgz > "$PAYLOAD/sums"
	printf '%s  %s\n' "$BB_SHA256" busybox >> "$PAYLOAD/sums"
	(cd "$PAYLOAD" && shasum -a 256 -c sums) || die "hash mismatch - do not push these files"
	rm -rf "$tmp"
	echo "ready: payload/acc.tgz + payload/busybox -> sh scripts/install-acc.sh push user@phone"
}

pc_push() {
	host=${2:?usage: sh scripts/install-acc.sh push user@host}
	[ -f "$PAYLOAD/busybox" ] || die "missing $PAYLOAD/busybox - run: sh scripts/install-acc.sh download"
	[ -f "$PAYLOAD/acc.tgz" ] || die "missing $PAYLOAD/acc.tgz - run: sh scripts/install-acc.sh download"
	scp -P 2222 "$PAYLOAD/busybox" "$PAYLOAD/acc.tgz" "$SELF" "$host:/sdcard/" || die "scp failed"
	echo "== launching device-side install =="
	ssh -p 2222 "$host" 'su -c "sh /sdcard/install-acc.sh run"'
}

# --------------------------------------------------------------------- entry

case "${1:-}" in
download) pc_download ;;
push) pc_push "$@" ;;
run) do_run ;;
status) do_status ;;
fix-init) do_fix_init ;;
online) do_online ;;
uninstall) do_uninstall ;;
*)
	sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
	exit 2
	;;
esac
