#!/system/bin/sh

MODDIR=${0%/*}
LOG=/data/adb/plf110_display_oc.log
LOG_LIMIT_BYTES=524288

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
        grep -Eq 'supportedRefreshRates.*144\.|fps=144\.'
}

reload_display_stack_if_needed() {
    # HWC snapshots its connector modes during startup.  Give the kernel
    # module and DRM hotplug a few seconds first; only restart the display
    # stack when the 144 Hz entry is genuinely still absent.
    sleep 0
    if display_has_144; then
        echo "[$(date '+%F %T')] display stack already sees 144Hz"
        return 0
    fi

    boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null |
        tr -cd '[:alnum:]-')
    [ -n "$boot_id" ] || boot_id=unknown
    state_dir=/data/adb/plf110_display_oc
    marker="$state_dir/display_reload.$boot_id"
    if [ -e "$marker" ]; then
        echo "[$(date '+%F %T')] display stack reload already attempted for boot=$boot_id"
        return 0
    fi
    mkdir -p "$state_dir"
    : > "$marker"
    chmod 0600 "$marker" 2>/dev/null

    echo "[$(date '+%F %T')] 144Hz missing; restarting vendor HWC once"
    setprop ctl.restart vendor.hwcomposer-3-2
    hwc_rc=$?
    echo "[$(date '+%F %T')] display stack reload requested hwc_rc=$hwc_rc"
    sleep 5
    if display_has_144; then
        echo "[$(date '+%F %T')] display stack reload restored 144Hz"
    else
        echo "[$(date '+%F %T')] display stack reload finished but 144Hz is still absent"
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
            # hotplug event itself. Do not restart vendor HWC here: that can
            # reinitialize unrelated vendor services, including charging and
            # power-policy HALs. A manual composer restart remains a diagnostic
            # option, but it is intentionally outside the boot path.
            echo "[$(date '+%F %T')] composer restart skipped: hotplug-only mode"
            ;;
        *)
            echo "[$(date '+%F %T')] install verification failed"
            ;;
    esac

    reload_display_stack_if_needed

    echo "[$(date '+%F %T')] worker done"
}

start_display_oc &
echo "[$(date '+%F %T')] service worker launched"

echo "[$(date '+%F %T')] ColorOS owns refresh policy; polling daemon disabled"
exit 0
