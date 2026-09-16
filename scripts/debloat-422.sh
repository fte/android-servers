#!/system/bin/sh
# debloat-422.sh - bloatware freezer/remover for Android 4.2.2 (root required)
#
# Android 4.2.2 has NO `pm uninstall --user 0` and NO `cmd package`
# (those appeared in Android 4.3+). Two reversible methods instead:
#   freeze : `pm disable`  -> package stays on /system, can be re-enabled
#   remove : rename APK in /system/app to .bak -> rename back to restore
#
# Usage (adb shell, then `su`):
#   sh /sdcard/debloat-422.sh list      # show which listed packages exist
#   sh /sdcard/debloat-422.sh review    # show APK paths + sizes, frozen state,
#                                       #   and total reclaimable space
#   sh /sdcard/debloat-422.sh           # freeze (disable) - safe, reversible
#   sh /sdcard/debloat-422.sh remove    # rename APKs to .bak - frees space
#   sh /sdcard/debloat-422.sh restore   # undo freeze + remove
#   sh /sdcard/debloat-422.sh adb       # print one adb uninstall command per app
#
# NEVER add these to the list:
#   com.android.vending (Play Store), com.google.android.gms, com.google.android.gsf,
#   com.android.systemui, com.android.phone, com.android.settings,
#   com.android.launcher*, com.sec.android.app.launcher,
#   com.android.providers.*, *.csc, SecContainer / Knox packages.
#
# Find more bloat on YOUR device with:
#   pm list packages -s | sort > /sdcard/packages.txt
# (then copy interesting names into PKGS below; missing ones are skipped)

mode="${1:-freeze}"

# ---- EDIT ME: bloat list (Jelly Bean era + Samsung TouchWiz) ----
PKGS="
com.android.apps.tag
com.android.dreams.basic
com.android.dreams.phototable
com.android.facelock
com.android.musicfx
com.android.noisefield
com.android.phasebeam
com.android.wallpaper.livepicker
com.google.android.configupdater
com.google.android.location
com.google.android.onetimeinitializer
com.google.android.partnersetup
com.google.android.setupwizard
com.samsung.clipboardsaveservice
com.sec.android.app.easylauncher
com.sec.android.app.minimode.res
com.sec.android.app.ringtoneBR
com.sec.android.app.personalization
com.sec.android.easysettings
com.sec.android.preloadinstaller
com.sec.android.provider.badge
com.sec.android.provider.logsprovider
com.sec.android.service.cm
com.sec.enterprise.mdm.services.simpin
com.sec.enterprise.mdm.services.sysscope
com.sec.enterprise.mdm.services.vpn
com.sec.esdk.elm
"

# android.googleSearch.googleSearchWidget
# com.arcsoft.picturesbest.app
# com.dropbox.android
# com.epson.mobilephone.samsungprintservice
# com.fmm.dm
# com.fmm.ds
# com.google.android.apps.books
# com.google.android.apps.docs
# com.google.android.apps.magazines
# com.google.android.apps.maps
# com.google.android.apps.plus
# com.google.android.apps.uploader
# com.google.android.backup
# com.google.android.feedback
# com.google.android.gm
# com.google.android.gms
# com.google.android.googlequicksearchbox
# com.google.android.gsf
# com.google.android.gsf.login
# com.google.android.marvin.talkback
# com.google.android.music
# com.google.android.play.games
# com.google.android.street
# com.google.android.syncadapters.bookmarks
# com.google.android.syncadapters.calendar
# com.google.android.syncadapters.contacts
# com.google.android.talk
# com.google.android.tts
# com.google.android.videos
# com.google.android.voicesearch
# com.google.android.youtube
# com.hp.android.printservice
# com.infraware.polarisviewer5
# com.lifevibes.trimapp
# com.monotype.android.font.chococooky
# com.monotype.android.font.cooljazz
# com.monotype.android.font.droidserifitalic
# com.monotype.android.font.rosemary
# com.monotype.android.font.samsungsans
# com.osp.app.signin
# com.samsung.SMT
# com.samsung.android.app.accesscontrol
# com.samsung.android.app.assistantmenu
# com.samsung.android.app.shareaccessibilitysettings
# com.samsung.android.service.travel
# com.samsung.android.tripwidget
# com.samsung.everglades.video
# com.samsung.helphub
# com.samsung.pickuptutorial
# com.samsung.shareshot
# com.sec.android.Kies
# com.sec.android.SimpleWidget
# com.sec.android.allshare.service.controlshare
# com.sec.android.allshare.service.fileshare
# com.sec.android.allshare.service.mediashare
# com.sec.android.app.FileShareClient
# com.sec.android.app.FileShareServer
# com.sec.android.app.browsertry
# com.sec.android.app.camera
# com.sec.android.app.clockpackage
# com.sec.android.app.collage
# com.sec.android.app.fm
# com.sec.android.app.kieswifi
# com.sec.android.app.memo
# com.sec.android.app.mobileprint
# com.sec.android.app.music
# com.sec.android.app.myfiles
# com.sec.android.app.popupcalculator
# com.sec.android.app.popupuireceiver
# com.sec.android.app.safetyassurance
# com.sec.android.app.samsungapps
# com.sec.android.app.sns3
# com.sec.android.app.translator
# com.sec.android.app.videoplayer
# com.sec.android.app.voicerecorder
# com.sec.android.app.wallpaperchooser
# com.sec.android.cloudagent
# com.sec.android.cloudagent.dropboxoobe
# com.sec.android.daemonapp
# com.sec.android.directconnect
# com.sec.android.directshare
# com.sec.android.gallery3d
# com.sec.android.motions.settings.panningtutorial
# com.sec.android.nearby.mediaserver
# com.sec.android.pagebuddynotisvc
# com.sec.android.provider.snote
# com.sec.android.sCloudBackupApp
# com.sec.android.sCloudBackupProvider
# com.sec.android.sCloudRelayData
# com.sec.android.sCloudSync
# com.sec.android.sCloudSyncBrowser
# com.sec.android.sCloudSyncCalendar
# com.sec.android.sCloudSyncContacts
# com.sec.android.sCloudSyncSNote
# com.sec.android.scloud.quota
# com.sec.android.widgetapp.SPlannerAppWidget
# com.sec.android.widgetapp.activeapplicationwidget
# com.sec.android.widgetapp.alarmwidget
# com.sec.android.widgetapp.ap.hero.accuweather
# com.sec.android.widgetapp.digitalclock
# com.sec.android.widgetapp.digitalclock2x1
# com.sec.android.widgetapp.dualclockdigital
# com.sec.android.widgetapp.easyfavoritescontactswidget
# com.sec.android.widgetapp.memo
# com.sec.android.widgetapp.webmanual
# com.sec.app.samsungprintservice
# com.sec.chaton
# com.sec.hearingadjust
# com.sec.pcw
# com.sec.pcw.device
# com.sec.spp.push
# com.siso.app.generic
# com.siso.app.genericprintservice
# com.tripadvisor.tripadvisor
# com.vlingo.midas
# com.wssnps
# com.wssyncmldm

# com.google.android.videos
# com.google.android.apps.books
# com.google.android.apps.magazines
# com.google.android.apps.plus
# com.google.android.talk
# com.google.android.apps.uploader
# com.google.android.feedback
# com.google.android.play.games
# com.sec.chaton
# com.sec.android.app.gamehub
# com.sec.readershub
# com.sec.android.app.samsungapps
# com.osp.app.signin
# com.sec.android.daemonapp
# com.sec.android.app.music
# com.sec.android.app.voicenote
# com.sec.android.app.sbrowser
# com.sec.android.app.fm# "
# Optional, uncomment to include:
#com.google.android.gm
#com.google.android.youtube
#com.google.android.music
#com.google.android.apps.maps
#com.google.android.partnersetup
# ---- end of list ----

# ==== REMOVAL LOG - wave 2 (2026-09-14, manual rm once 'review' showed wave 1 done) ====
# Removed from /system/app (APK + matching .odex), owners verified via `pm path`:
#   com.android.email                       SecEmail_J.apk             ~17 MB
#   com.android.exchange                    SecExchange.apk             ~8 MB
#   com.android.browser                     SecBrowser.apk              ~6 MB  (links open in Chrome now)
#   com.sec.android.app.launcher            SecLauncher3.apk            ~5 MB  ⚠️ SEE BELOW - was restored
#   com.sec.android.app.hwmoduletest        HwModuleTest.apk
#   com.sec.android.app.factorykeystring    FactoryKeystring_FB.apk
#   com.sec.android.AutoPreconfig           AutoPreconfig.apk
#   com.sec.android.Preconfig               Preconfig.apk
#   com.sec.android.app.sysscope            SysScope.apk       (chattr -i needed)
#   com.sec.android.fotaclient              FotaClient.apk     (chattr -i needed; OTA dead, device EOL)
#   com.sec.android.app.mt                  MobileTrackerEngineTwo.apk (chattr -i needed)
#   com.sec.android.app.parser              SCParser.apk       (chattr -i needed)
#   com.sec.android.app.tmserver            TMServerApp.apk    (chattr -i needed)
#   com.sec.android.app.nfctest             NfcTest.apk
#   com.sec.android.app.wlantest            WlanTest.apk
#   com.sec.android.app.bluetoothtest       BluetoothTest.apk
#   com.sec.android.app.servicemodeapp      serviceModeApp_FB.apk
#   com.sec.android.RilServiceModeApp       ServiceModeApp_RIL.apk
#   com.sec.android.app.DataCreate          AutomationTest_FB.apk
#
# Removed from /system/lib (~95 MB, owner apps already gone after wave 1):
#   libpolaris*                             Polaris Office viewer
#   libASP15_* libcupsgs.so                 AllShare / CUPS print backends
#   libfacerecognition.so libdmcFaceEngine.so
#   libdmcFaceEngine3GVT.so libfrsdk.so      face recognition
#   libgoogle_recognizer_jni_l.so
#   libpatts_engine_jni_api_ub.210030011.so  voice recognition
#   libsamsungtts.so libvideochat_jni.so
#   libmoviemaker-jni.so libarcpicbest.so
#   liblifevibes_mediashare_hw_jni.so
#   liblifevibes_mediashare_sw_jni.so
#   libswiftkeysdk-java.so                  SwiftKey SDK - ⚠️ RESTORED 2026-09-14:
#              needed by the Samsung keyboard (SamsungIME/DIOTEK IME, Java-side
#              System.loadLibrary). Deleting it = 'Samsung keyboard has stopped'
#              crash-loop (UnsatisfiedLinkError on com.touchtype_fluency.SwiftKeySDK).
#   libSamsungPDLComposer_MD2.so             printer driver
#
# KEPT ON PURPOSE:
#   /system/app/ChromeWithBrowser.apk - dual-registered with the updated Chrome
#   in /data/app (dumpsys shows both codePaths). Deleting the base APK can make
#   PackageManager drop Chrome entirely at boot, and the 4.2.2-era Play Store
#   may no longer serve a compatible build. 12 MB not worth the risk.
#
# Quirk learned: some Samsung security APKs survive `rm` even on a rw /system
#   until `busybox chattr -i <file>` runs first - even when lsattr shows no i
#   flag (seen on FotaClient, MobileTrackerEngineTwo, SCParser, TMServerApp).
#
# ==== BOOT BROKE TWICE - lessons (2026-09-14) ====
# 1. libdmcFaceEngine.so is NOT an orphan! Despite its name it is linked by
#    libseccameracore.so -> libsecface.so -> libcameraservice.so -> mediaserver.
#    Deleting it made mediaserver crash-loop (init 'media' exit 255), so no
#    media.player/audio_policy services -> boot stalls forever with logcat
#    'Waiting for service media.player'. Restored from stock system.img.
#    LESSON: before deleting any /system/lib, walk DT_NEEDED of /system/bin
#    execs recursively (see walk-deps.py approach), never trust the name.
# 2. SecLauncher3 (TouchWiz) IS the real home screen. 'com.google.android.launcher'
#    on this device is only a redirect STUB (version 1.3.large, StubApp +
#    LauncherRedirectionProvider, no HOME activity). Removing TouchWiz left the
#    system with zero android.intent.category.HOME activities -> bootanim never
#    exits, mFocusedActivity stays null although 'System now ready' is logged.
#    Restored SecLauncher3.apk + matching .odex from stock system.img.
#    LESSON: never remove the active launcher on 4.2.2 without verifying a real
#    HOME activity exists: dumpsys package <pkg> must list a MAIN/HOME filter.
# Diagnosis flow that worked: getprop sys.boot_completed / init.svc.media;
#   run /system/bin/mediaserver by hand to see linker errors; grep logcat for
#   'Waiting for service'; check mFocusedActivity for HOME resolution.
# 2b. walk-deps.py only walks DT_NEEDED of /system/bin executables. Libraries
#    loaded from Java via System.loadLibrary() inside an APK (like the Samsung
#    keyboard loading libswiftkeysdk-java.so) are INVISIBLE to it. Before
#    deleting a lib, also check: grep the pulled /system/app APKs for the lib
#    base name, or better: keep every lib whose name matches no obvious owner
#    unless proven otherwise.
# 3. Symptom of a missing IME lib: 'Clavier Samsung s'est arreté' popup loop.
#    Crash signature in logcat: UnsatisfiedLinkError while initializing
#    Lcom/touchtype_fluency/SwiftKeySDK; stack from
#    com.diotek.ime...InputControllerImpl.initInputEngine.
#    Fix = restore the lib, then reopen a text field; verify with
#    'dumpsys input_method' (curSession=SessionState{...} must appear).
# ==== end lessons ====
#
# Result (final, incl. restored launcher+lib): /system 758M used / 714 MB free
#   (was 1.34G used / 99 MB free).  /data: 4.59 GB free.
# ==== end removal log ====

installed() {
	out=$(pm path "$1" 2>/dev/null)
	case "$out" in
	package:*) return 0 ;;
	*) return 1 ;;
	esac
}

# bytes -> human readable (no awk/stat/du needed on stock 4.2.2 toolbox)
fmtsize() {
	b=$1
	case "$b" in ''|*[!0-9]*) b=0 ;; esac
	if [ "$b" -ge 1048576 ]; then
		echo "$((b/1048576)).$(( (b%1048576)*10/1048576 )) MB"
	elif [ "$b" -ge 1024 ]; then
		echo "$((b/1024)).$(( (b%1024)*10/1024 )) KB"
	else
		echo "${b} B"
	fi
}

# file size in bytes via plain `ls -l` (field 5 in both toolbox and busybox ls)
filesize() {
	set -- $(ls -l "$1" 2>/dev/null)
	sz=$5
	case "$sz" in ''|*[!0-9]*) echo 0 ;; *) echo "$sz" ;; esac
}

isfrozen() {
	# Method 1: `pm list packages -d` exists only on Android 4.3+; on 4.2 it
	# fails with "Unknown option" (non-zero exit, empty output).
	out=$(pm list packages -d 2>/dev/null)
	if [ $? -eq 0 ]; then
		case "$out" in
		*"package:$1"*) return 0 ;;
		*) return 1 ;;
		esac
	fi
	# Method 2 (4.2 fallback): dumpsys reports the enabled state:
	#   0=default 1=enabled 2=disabled 3=disabled-by-user 4=disabled-until-used
	ds=$(dumpsys package "$1" 2>/dev/null)
	case "$ds" in
	*"enabled=2"*|*"enabled=3"*|*"enabled=4"*) return 0 ;;
	*) return 1 ;;
	esac
}

# total bytes an installed package occupies on /system (apk + odex)
apksize() {
	total=0
	for line in $(pm path "$1" 2>/dev/null); do
		case "$line" in
		package:/system/*)
			apk="${line#package:}"
			total=$(( total + $(filesize "$apk") ))
			odex="${apk%.apk}.odex"
			[ -f "$odex" ] && total=$(( total + $(filesize "$odex") ))
			;;
		esac
	done
	echo "$total"
}

remount_rw() {
	mount -o remount,rw /system 2>/dev/null
	if touch /system/.rwtest 2>/dev/null; then rm -f /system/.rwtest; return 0; fi
	busybox mount -o remount,rw /system 2>/dev/null
	if touch /system/.rwtest 2>/dev/null; then rm -f /system/.rwtest; return 0; fi
	return 1
}

remount_ro() {
	mount -o remount,ro /system 2>/dev/null ||
		busybox mount -o remount,ro /system 2>/dev/null
	return 0
}

case "$mode" in
adb|adb-remove|commands)
	for p in $PKGS; do
		echo "adb shell pm uninstall \"$p\""
	done
	;;

list)
	for p in $PKGS; do
		if installed "$p"; then
			echo "PRESENT  $p"
		else
			echo "absent   $p"
		fi
	done
	;;

review)
	present=0
	absent=0
	total=0
	echo "state   size       package"
	echo "------  ---------  --------------------------------"
	for p in $PKGS; do
		if ! installed "$p"; then
			echo "absent             $p"
			absent=$((absent+1))
			continue
		fi
		present=$((present+1))
		sz=$(apksize "$p")
		total=$((total+sz))
		state="active"
		if isfrozen "$p"; then state="FROZEN"; fi
		echo "$state  $(fmtsize "$sz")  $p"
		for line in $(pm path "$p" 2>/dev/null); do
			case "$line" in
			package:/system/*) echo "           ${line#package:}" ;;
			package:/data/*)   echo "           ${line#package:}  (updated in /data)" ;;
			esac
		done
		[ -d "/data/data/$p" ] && echo "           /data/data/$p  (deleted only by 'remove')"
	done
	echo "------"
	echo "$present present, $absent absent"
	echo "reclaimable on /system with 'remove': $(fmtsize "$total")"
	;;

freeze)
	pm list packages -s > /sdcard/packages-backup.txt 2>/dev/null
	for p in $PKGS; do
		if installed "$p"; then
			echo "freezing $p"
			pm disable "$p"
		else
			echo "absent   $p"
		fi
	done
	echo "done. undo with: sh $0 restore"
	;;

remove)
	pm list packages -s > /sdcard/packages-backup.txt 2>/dev/null
	remount_rw || { echo "ERROR: cannot remount /system read-write"; exit 1; }
	for p in $PKGS; do
		if installed "$p"; then
			echo "removing $p"
			# drop any /data update of a system app first (ignore failure)
			pm uninstall "$p" 2>/dev/null
			for line in $(pm path "$p" 2>/dev/null); do
				case "$line" in
				package:/system/*)
					apk="${line#package:}"
					echo "  $(fmtsize "$(apksize "$p")")  $apk"
					mv "$apk" "$apk.bak" 2>/dev/null
					odex="${apk%.apk}.odex"
					[ -f "$odex" ] && mv "$odex" "$odex.bak" 2>/dev/null
					echo "  moved $apk -> .bak"
					;;
				esac
			done
			rm -rf "/data/data/$p" "/data/app-lib/$p" 2>/dev/null
			rm -f /data/app/"$p"-*.apk 2>/dev/null
		else
			echo "absent   $p"
		fi
	done
	remount_ro
	echo "done. reboot the device. undo with: sh $0 restore"
	;;

restore)
	remount_rw || { echo "ERROR: cannot remount /system read-write"; exit 1; }
	for f in /system/app/*.bak; do
		[ -e "$f" ] || continue
		mv "$f" "${f%.bak}"
		echo "restored ${f%.bak}"
	done
	remount_ro
	for p in $PKGS; do
		pm enable "$p" 2>/dev/null
	done
	echo "done. reboot the device."
	;;

*)
	echo "unknown mode: $mode (use: list | review | freeze | remove | restore)"
	exit 1
	;;
esac
