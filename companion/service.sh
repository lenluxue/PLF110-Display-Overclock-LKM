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
CAPTURE_DIR=/data/local/tmp/plf110-capture
CAPTURE_RETENTION_HOURS=24
CAPTURE_CLEAN_INTERVAL=86400
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

prune_capture_logs() {
    [ -d "$CAPTURE_DIR" ] || return 0
    pruned=$(find "$CAPTURE_DIR" -maxdepth 1 -type f -mtime +${CAPTURE_RETENTION_HOURS}h -print -delete 2>/dev/null | wc -l)
    case "$pruned" in
        ''|*[!0-9]*) pruned=0 ;;
    esac
    echo "[$(date '+%F %T')] capture cleanup retention=${CAPTURE_RETENTION_HOURS}h pruned=$pruned"
}

start_capture_cleanup() {
    prune_capture_logs
    (
        while :; do
            sleep "$CAPTURE_CLEAN_INTERVAL"
            prune_capture_logs
        done
    ) &
    echo "[$(date '+%F %T')] capture cleanup worker launched interval=${CAPTURE_CLEAN_INTERVAL}s"
}

display_has_144() {
    dumpsys display 2>/dev/null |
        grep -Eq 'fps=144\.|supportedRefreshRates.*144\.'
}

wait_for_display_ready() {
    seconds=$1
    i=0
    while [ "$i" -lt "$seconds" ]; do
        if [ "$(getprop sys.boot_completed)" = 1 ] &&
           [ "$(getprop init.svc.bootanim)" = stopped ]; then
            return 0
        fi
        i=$((i + 1))
        sleep 1
    done
    return 1
}

raise_global_refresh_ceiling() {
    peak_rc=0
    user_rc=0
    settings put system peak_refresh_rate 144.0 >/dev/null 2>&1 || peak_rc=$?
    settings put secure user_refresh_rate 144 >/dev/null 2>&1 || user_rc=$?
    echo "[$(date '+%F %T')] global refresh ceiling peak_rc=$peak_rc user_rc=$user_rc peak=$(settings get system peak_refresh_rate 2>/dev/null) user=$(settings get secure user_refresh_rate 2>/dev/null)"
}

maintain_global_refresh_ceiling() {
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

RATE_RESPECT_INTERVAL=3
RATE_RESPECT_EXCLUDE=com.android.systemui

policy_144_packages() {
    sed -n 's/.*<item package="\([^"]*\)" rateId="4-.*/\1/p' "$SMART_CONFIG_TARGET" 2>/dev/null
}

scan_screenmode_state() {
    dumpsys oplusscreenmode 2>/dev/null | awk '
        /^pickWin:/ {
            if (pick == "") {
                pick = $0
                sub(/.*[ {]/, "", pick)
                sub(/\/.*/, "", pick)
            }
        }
        /dAlwaysRespectAppRequestedMode *=/ {
            flag = ($0 ~ /=true/) ? "true" : "false"
        }
        {
            count = split($0, entries, ";")
            if (count < 2) next
            for (i = 1; i <= count; i++) {
                entry = entries[i]
                sub(/^[[:space:]]*/, "", entry)
                colon = index(entry, ":")
                if (colon < 2) continue
                package = substr(entry, 1, colon - 1)
                rates = substr(entry, colon + 1)
                gsub(/[[:space:]]/, "", rates)
                if (package !~ /^[A-Za-z0-9_][A-Za-z0-9_.]*$/ || rates !~ /^[0-9-]+$/) continue
                rate_count = split(rates, rate_ids, "-")
                valid = (rate_count == 4)
                for (j = 1; j <= rate_count; j++) {
                    if (rate_ids[j] !~ /^[0-9]+$/) valid = 0
                }
                if (valid && rate_ids[4] == "4" && index(" " user_packages " ", " " package " ") == 0) {
                    user_packages = user_packages (user_packages == "" ? "" : " ") package
                }
            }
        }
        END {
            print (pick == "" ? "-" : pick), (flag == "" ? "-" : flag)
            print user_packages
        }
    '
}

set_app_request_respect() {
    dumpsys oplusscreenmode always_respet_apprequestedmode "$1" >/dev/null 2>&1
}

maintain_app_request_respect() {
    until [ "$(getprop sys.boot_completed)" = 1 ]; do
        if [ -e "$MODDIR/disable" ] || [ -e "$MODDIR/remove" ]; then
            return 0
        fi
        sleep 5
    done
    sleep 25
    game_list=$(policy_144_packages | grep -v "^$RATE_RESPECT_EXCLUDE\$")
    echo "[$(date '+%F %T')] app request watchdog start xml_entries=$(printf '%s\n' "$game_list" | grep -c .) dynamic_user_144=enabled interval=${RATE_RESPECT_INTERVAL}s"
    active=0
    tick=0
    while :; do
        if [ -e "$MODDIR/disable" ] || [ -e "$MODDIR/remove" ]; then
            if [ "$active" = 1 ]; then
                set_app_request_respect 0
                active=0
            fi
            sleep 30
            continue
        fi
        state=$(scan_screenmode_state)
        set -- $state
        pick_pkg=$1
        flag_state=$2
        shift 2
        user_144_list=$*
        [ "$pick_pkg" = "-" ] && pick_pkg=
        [ "$flag_state" = "-" ] && flag_state=
        want=0
        if [ -n "$pick_pkg" ]; then
            for rate_package in $game_list $user_144_list; do
                [ "$rate_package" = "$RATE_RESPECT_EXCLUDE" ] && continue
                if [ "$rate_package" = "$pick_pkg" ]; then
                    want=1
                    break
                fi
            done
        fi
        tick=$((tick + 1))
        if [ "$want" != "$active" ]; then
            set_app_request_respect "$want"
            active=$want
            if [ "$want" = 1 ]; then
                echo "[$(date '+%F %T')] app request priority ON for $pick_pkg"
            else
                echo "[$(date '+%F %T')] app request priority OFF (pick=${pick_pkg:-none})"
            fi
        elif [ "$want" = 1 ] && [ "$flag_state" != true ]; then
            set_app_request_respect 1
            echo "[$(date '+%F %T')] app request priority re-applied for $pick_pkg"
        elif [ "$want" = 1 ] && [ $((tick % 40)) = 0 ]; then
            echo "[$(date '+%F %T')] app request priority held for $pick_pkg"
        fi
        sleep "$RATE_RESPECT_INTERVAL"
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

restart_vendor_hwc_after_boot() {
    boot_marker="$STATE_DIR/hwc_restart.$BOOT_ID"
    if [ -e "$boot_marker" ]; then
        echo "[$(date '+%F %T')] vendor HWC restart already done for boot=$BOOT_ID"
        return 0
    fi
    if ! pidof surfaceflinger >/dev/null 2>&1; then
        echo "[$(date '+%F %T')] SurfaceFlinger missing; skipped vendor HWC restart"
        return 0
    fi
    if [ "$(getprop init.svc.vendor.hwcomposer-3-2)" != running ]; then
        echo "[$(date '+%F %T')] vendor HWC service not running; skipped vendor HWC restart"
        return 0
    fi
    if [ -e "$HWC_RELOAD_DISABLED" ]; then
        echo "[$(date '+%F %T')] $HWC_RELOAD_DISABLED present; forcing restart anyway"
    fi
    mkdir -p "$STATE_DIR"
    : > "$boot_marker"
    chmod 0600 "$boot_marker" 2>/dev/null

    echo "[$(date '+%F %T')] restarting vendor HWC after boot completed (boot=$BOOT_ID)"
    setprop ctl.restart vendor.hwcomposer-3-2
    echo "[$(date '+%F %T')] vendor HWC restart rc=$? sf_pid=$(pidof surfaceflinger 2>/dev/null | tr ' ' ',')"
    sleep 10
    echo "[$(date '+%F %T')] framework refresh rates after HWC restart: $(dumpsys display 2>/dev/null | grep -o 'fps=[0-9.]*' | sort -u | tr '\n' ',')"
    if display_has_144; then
        echo "[$(date '+%F %T')] framework sees 144Hz after HWC restart"
    else
        echo "[$(date '+%F %T')] framework does not list 144Hz after HWC restart"
    fi
}

start_brightness_compensation() {
    if ! display_has_144; then
        echo "[$(date '+%F %T')] brightness compensation skipped: framework 144Hz absent"
        return 0
    fi
    if [ ! -x "$MODDIR/bin/plf110-brightness-comp" ]; then
        echo "[$(date '+%F %T')] brightness compensation binary unavailable"
        return 0
    fi
    # This worker reads the actual hopping state and original LED request.
    # It does not rewrite the Android brightness setting.
    "$MODDIR/bin/plf110-brightness-comp" 100 0 "$MODDIR/brightness.conf" "$MODDIR" &
    echo "[$(date '+%F %T')] brightness compensation worker launched"
}

post_boot_display_check() {
    if ! wait_for_display_ready 180; then
        echo "[$(date '+%F %T')] display-ready state not seen within 180s; boot guard will roll back on next boot"
        return 0
    fi
    accept_policy_after_boot
    raise_global_refresh_ceiling
    maintain_global_refresh_ceiling &
    echo "[$(date '+%F %T')] global refresh ceiling maintenance scheduled"

    echo "[$(date '+%F %T')] framework refresh rates: $(dumpsys display 2>/dev/null | grep -o 'fps=[0-9.]*' | sort -u | tr '\n' ',')"
    restart_vendor_hwc_after_boot
    start_brightness_compensation
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
            echo "[$(date '+%F %T')] composer restart skipped: hotplug-only mode"
            ;;
        *)
            echo "[$(date '+%F %T')] install verification failed"
            ;;
    esac

    post_boot_display_check
    echo "[$(date '+%F %T')] worker done"
}

start_capture_cleanup
start_display_oc &
echo "[$(date '+%F %T')] service worker launched"

maintain_app_request_respect &
echo "[$(date '+%F %T')] app request watchdog launched"

echo "[$(date '+%F %T')] ColorOS owns refresh policy; only the app request watchdog runs"
exit 0
