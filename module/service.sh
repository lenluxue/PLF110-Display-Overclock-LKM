#!/system/bin/sh

MODDIR=${0%/*}
LOG=/data/adb/plf110_display_oc.log
LOG_LIMIT_BYTES=524288
STATE_DIR=/data/adb/plf110_display_oc
GUARD_DIR="$STATE_DIR/boot-guard"
GUARD_PENDING="$GUARD_DIR/policy.pending"
GUARD_LASTGOOD="$GUARD_DIR/refresh_rate_config.lastgood.xml"
GUARD_EVENTS="$GUARD_DIR/events.log"
SMART_CONFIG_TARGET=/data/system/refresh_rate_config.xml
HWC_RELOAD_DISABLED="$STATE_DIR/hwc_reload.disabled"
BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null | tr -cd '[:alnum:]-')
[ -n "$BOOT_ID" ] || BOOT_ID=unknown

rotate_log() {
    [ -f "$LOG" ] || return 0
    log_size=$(wc -c < "$LOG" 2>/dev/null)
    case "$log_size" in
        ''|*[!0-9]*) return 0 ;;
    esac
    if [ "$log_size" -gt "$LOG_LIMIT_BYTES" ]; then
        log_tmp="$LOG.trim.$$"
        if tail -n 1000 "$LOG" > "$log_tmp" 2>/dev/null; then
            chmod 0600 "$log_tmp" 2>/dev/null
            mv -f "$log_tmp" "$LOG"
        else
            rm -f "$log_tmp"
        fi
    fi
}

mkdir -p /data/adb
rotate_log
exec >>"$LOG" 2>&1
echo "[$(date '+%F %T')] service start (async)"

snapshot_runtime() {
    label=$1
    sf_pid=$(pidof surfaceflinger 2>/dev/null | tr ' ' ',')
    hwc_pid=$(pidof android.hardware.graphics.composer@3.2-service 2>/dev/null | tr ' ' ',')
    battery=$(cat /sys/class/power_supply/battery/uevent 2>/dev/null |
        grep -E 'POWER_SUPPLY_(STATUS|CHARGE_TYPE|CAPACITY|VOLTAGE_NOW|CURRENT_NOW|TEMP)=' |
        tr '\n' ' ')
    usb=$(cat /sys/class/power_supply/usb/uevent 2>/dev/null |
        grep -E 'POWER_SUPPLY_(ONLINE|VOLTAGE_NOW|CURRENT_NOW|VOLTAGE_MAX|CURRENT_MAX)=' |
        tr '\n' ' ')
    primary=$(cat /sys/class/power_supply/primary_chg/uevent 2>/dev/null |
        grep -E 'POWER_SUPPLY_(ONLINE|VOLTAGE_NOW|CURRENT_NOW|VOLTAGE_MAX|CURRENT_MAX)=' |
        tr '\n' ' ')
    charge=$(dumpsys battery 2>/dev/null |
        grep -E 'Charger voltage|Battery current|ChargerTechnology|ChargeFastCharger|Max charging (current|voltage)' |
        tr '\n' ' ')
    echo "[$(date '+%F %T')] snapshot=$label sf_pid=${sf_pid:-none} hwc_pid=${hwc_pid:-none}"
    echo "[$(date '+%F %T')] snapshot=$label battery={$battery} usb={$usb} primary_chg={$primary}"
    echo "[$(date '+%F %T')] snapshot=$label framework_charge={$charge}"
    if [ -r /sys/module/PLF110_Display_OC/parameters/status ]; then
        echo "[$(date '+%F %T')] snapshot=$label kernel=$(cat /sys/module/PLF110_Display_OC/parameters/status)"
    fi
}

display_has_144() {
    dumpsys display 2>/dev/null |
        grep -Eq 'fps=144\.|supportedRefreshRates.*144\.'
}

wait_for_boot_completed() {
    seconds=$1
    i=0
    while [ "$i" -lt "$seconds" ]; do
        [ "$(getprop sys.boot_completed)" = 1 ] && return 0
        i=$((i + 1))
        sleep 1
    done
    return 1
}

raise_global_refresh_ceiling() {
    # ColorOS keeps a separate user/global ceiling. If it remains at 120 Hz,
    # per-app 144 Hz entries are parsed but DisplayManager clamps them back to
    # 120 Hz. Apply this only after boot is complete so SettingsProvider and
    # DisplayManager are ready; the XML policy still chooses 120/60/144 per app.
    peak_rc=0
    user_rc=0
    settings put system peak_refresh_rate 144.0 >/dev/null 2>&1 || peak_rc=$?
    settings put secure user_refresh_rate 144 >/dev/null 2>&1 || user_rc=$?
    echo "[$(date '+%F %T')] global refresh ceiling peak_rc=$peak_rc user_rc=$user_rc peak=$(settings get system peak_refresh_rate 2>/dev/null) user=$(settings get secure user_refresh_rate 2>/dev/null)"
}

maintain_global_refresh_ceiling() {
    # Some ColorOS display services rewrite the setting during the first
    # minute after boot. Retry only during that startup window; no HWC or
    # SurfaceFlinger process is touched.
    for delay in 15 30 60 120; do
        sleep "$delay"
        [ "$(getprop sys.boot_completed)" = 1 ] || continue
        current_peak=$(settings get system peak_refresh_rate 2>/dev/null)
        current_user=$(settings get secure user_refresh_rate 2>/dev/null)
        case "$current_peak:$current_user" in
            144.0:144|144:144)
                echo "[$(date '+%F %T')] global refresh ceiling still active peak=$current_peak user=$current_user"
                ;;
            *)
                echo "[$(date '+%F %T')] global refresh ceiling changed peak=$current_peak user=$current_user; restoring 144Hz"
                raise_global_refresh_ceiling
                ;;
        esac
    done
}

accept_policy_after_boot() {
    [ -f "$GUARD_PENDING" ] || return 0
    pending_boot=$(sed -n 's/^boot_id=//p' "$GUARD_PENDING" 2>/dev/null | head -n 1)
    if [ "$pending_boot" != "$BOOT_ID" ]; then
        echo "[$(date '+%F %T')] stale policy.pending from boot=$pending_boot kept for next-boot rollback"
        return 0
    fi
    mkdir -p "$GUARD_DIR" 2>/dev/null
    chmod 0700 "$GUARD_DIR" 2>/dev/null
    config_sha=$(sha256sum "$SMART_CONFIG_TARGET" 2>/dev/null | awk '{print $1}')
    if [ -r "$SMART_CONFIG_TARGET" ]; then
        cp -f "$SMART_CONFIG_TARGET" "$GUARD_LASTGOOD" 2>/dev/null
        chmod 0600 "$GUARD_LASTGOOD" 2>/dev/null
    fi
    echo "[$(date '+%F %T')] boot=$BOOT_ID policy config accepted sha256=$config_sha"
    echo "[$(date '+%F %T')] boot=$BOOT_ID policy accepted sha256=$config_sha" >> "$GUARD_EVENTS" 2>/dev/null
    rm -f "$GUARD_PENDING"
}

post_boot_display_check() {
    # Never touch the display stack while the framework is still starting. An
    # earlier build restarted vendor HWC during boot; system_server then blocked
    # forever on a dead SurfaceFlinger (see the ANR pre-watchdog traces), which
    # looked like a frozen screen with no crash log.
    if ! wait_for_boot_completed 180; then
        echo "[$(date '+%F %T')] boot_completed not seen within 180s; boot guard will roll back on next boot"
        return 0
    fi
    accept_policy_after_boot
    raise_global_refresh_ceiling
    maintain_global_refresh_ceiling &
    echo "[$(date '+%F %T')] global refresh ceiling maintenance scheduled"

    # boot_completed means the home screen is available; a short grace period
    # is enough for the second desktop/page transition without touching HWC
    # during the fragile early-boot window.
    sleep 5
    echo "[$(date '+%F %T')] framework refresh rates: $(dumpsys display 2>/dev/null | grep -o 'fps=[0-9.]*' | sort -u | tr '\n' ',')"
    if display_has_144; then
        echo "[$(date '+%F %T')] framework sees 144Hz after boot"
        return 0
    fi

    if [ -e "$HWC_RELOAD_DISABLED" ]; then
        echo "[$(date '+%F %T')] framework does not list 144Hz; vendor HWC reload disabled by $HWC_RELOAD_DISABLED"
        return 0
    fi

    boot_id_marker="$STATE_DIR/display_reload.$BOOT_ID"
    if [ -e "$boot_id_marker" ]; then
        echo "[$(date '+%F %T')] vendor HWC reload already attempted for boot=$BOOT_ID"
        return 0
    fi
    if ! pidof surfaceflinger >/dev/null 2>&1; then
        echo "[$(date '+%F %T')] SurfaceFlinger missing; skipped vendor HWC reload"
        return 0
    fi
    mkdir -p "$STATE_DIR"
    : > "$boot_id_marker"
    chmod 0600 "$boot_id_marker" 2>/dev/null

    echo "[$(date '+%F %T')] delayed vendor HWC reload requested after boot"
    setprop ctl.restart vendor.hwcomposer-3-2
    echo "[$(date '+%F %T')] vendor HWC reload rc=$? sf_pid=$(pidof surfaceflinger 2>/dev/null | tr ' ' ',')"
    sleep 10
    if display_has_144; then
        echo "[$(date '+%F %T')] vendor HWC reload restored 144Hz"
    else
        echo "[$(date '+%F %T')] vendor HWC reload finished without 144Hz; disabling future automatic reloads"
        : > "$HWC_RELOAD_DISABLED"
        chmod 0600 "$HWC_RELOAD_DISABLED" 2>/dev/null
    fi
}

start_display_oc() {

    snapshot_runtime service_entry

    if [ ! -d /sys/module/PLF110_Display_OC ]; then
        insmod "$MODDIR/PLF110_Display_OC.ko"
        echo "[$(date '+%F %T')] insmod rc=$?"
    else
        echo "[$(date '+%F %T')] module already loaded"
    fi

    captured=0
    i=0
    while [ "$i" -lt 90 ]; do
        if [ -r /sys/module/PLF110_Display_OC/parameters/status ]; then
            status=$(cat /sys/module/PLF110_Display_OC/parameters/status)
            echo "[$(date '+%F %T')] status $status"
            case "$status" in
                *captured=1*) captured=1; break ;;
            esac
        fi
        i=$((i + 1))
        sleep 1
    done

    if [ "$captured" -ne 1 ]; then
        echo "[$(date '+%F %T')] capture timeout"
        return 1
    fi

    echo 1 > /sys/module/PLF110_Display_OC/parameters/enable
    echo "[$(date '+%F %T')] enable rc=$?"
    status=$(cat /sys/module/PLF110_Display_OC/parameters/status)
    echo "[$(date '+%F %T')] enabled $status"
    snapshot_runtime after_enable

    case "$status" in
        *installed=1*"modes=5"*"mtk_modes=5"*)
            # The module rebuilds the MTK connector/CRTC list and emits a DRM
            # hotplug event itself, so the display stack picks the new mode up
            # without a composer restart.
            echo "[$(date '+%F %T')] composer restart skipped: hotplug-only mode"
            ;;
        *)
            echo "[$(date '+%F %T')] install verification failed"
            ;;
    esac

    post_boot_display_check

    echo "[$(date '+%F %T')] worker done"
}

start_display_oc &
echo "[$(date '+%F %T')] service worker launched"

echo "[$(date '+%F %T')] ColorOS owns refresh policy; polling daemon disabled"
exit 0
