#!/system/bin/sh

MODDIR=${0%/*}
LOG=/data/adb/plf110_display_oc.log
LOG_LIMIT_BYTES=524288
STATE_DIR=/data/adb/plf110_display_oc
OEM_CONFIG_SOURCE=/my_product/etc/refresh_rate_config.xml
SMART_CONFIG_TARGET=/data/system/refresh_rate_config.xml
SMART_CONFIG_STATE="$STATE_DIR/refresh_config.state"
SMART_CONFIG_BACKUP="$STATE_DIR/refresh_rate_config.original.xml"
MODE_SOURCE_CACHE="$STATE_DIR/mode_source.cache"
FEATURE_SOURCE="$MODDIR/my_product/etc/permissions/oplus.product.display_features.xml"
FEATURE_TARGET="/my_product/etc/permissions/oplus.product.display_features.xml"

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
echo "[$(date '+%F %T')] post-fs-data early loader start"

# KernelSU does not mount this device's system_ext module overlay. Replace the
# existing Oplus feature file in my_product instead; this is the partition that
# OplusFeatureConfigManager scans for static <oplus-feature> entries.
if [ -r "$FEATURE_SOURCE" ] && [ -e "$FEATURE_TARGET" ]; then
    mount --bind "$FEATURE_SOURCE" "$FEATURE_TARGET"
    feature_rc=$?
    echo "[$(date '+%F %T')] Oplus feature bind rc=$feature_rc target=$FEATURE_TARGET"
else
    echo "[$(date '+%F %T')] Oplus feature source/target unavailable source=$FEATURE_SOURCE target=$FEATURE_TARGET"
fi

# ColorOS maps the native 144 Hz entry to ID 4. Start from this device's own product
# configuration on every boot and change only its max-setting ceiling; this
# preserves every OEM package/scene rule and future ROM update.
if [ -r "$OEM_CONFIG_SOURCE" ]; then
    mkdir -p "$STATE_DIR"
    chmod 0700 "$STATE_DIR" 2>/dev/null

    # Keep the OEM file as the single runtime source for ColorOS mode IDs.
    # The kernel keeps its validated timing constants separately, but every
    # status consumer reads this generated map instead of duplicating policy
    # IDs in shell/UI code.
    source_hash=$(sha256sum "$OEM_CONFIG_SOURCE" 2>/dev/null | awk '{print $1}')
    source_max_id=$(sed -n 's/.*maxrefreshsettings="\([0-9][0-9]*\)".*/\1/p' "$OEM_CONFIG_SOURCE" | tail -n 1)
    source_60_id=$(sed -n 's/.*\([0-9][0-9]*\)(60Hz).*/\1/p' "$OEM_CONFIG_SOURCE" | head -n 1)
    source_90_id=$(sed -n 's/.*\([0-9][0-9]*\)(90Hz).*/\1/p' "$OEM_CONFIG_SOURCE" | head -n 1)
    source_120_id=$(sed -n 's/.*\([0-9][0-9]*\)(120Hz).*/\1/p' "$OEM_CONFIG_SOURCE" | head -n 1)
    source_144_id=$(sed -n 's/.*\([0-9][0-9]*\)(144Hz).*/\1/p' "$OEM_CONFIG_SOURCE" | head -n 1)
    mode_source_tmp="$MODE_SOURCE_CACHE.tmp.$$"
    {
        echo "source_config=$OEM_CONFIG_SOURCE"
        echo "source_sha256=${source_hash:-unknown}"
        echo "source_max_id=${source_max_id:-unknown}"
        echo "source_60_id=${source_60_id:-unknown}"
        echo "source_90_id=${source_90_id:-unknown}"
        echo "source_120_id=${source_120_id:-unknown}"
        echo "source_144_id=${source_144_id:-unknown}"
    } > "$mode_source_tmp"
    chmod 0600 "$mode_source_tmp" 2>/dev/null
    mv -f "$mode_source_tmp" "$MODE_SOURCE_CACHE"

    if [ ! -f "$SMART_CONFIG_STATE" ]; then
        if [ -f "$SMART_CONFIG_TARGET" ]; then
            cp -pf "$SMART_CONFIG_TARGET" "$SMART_CONFIG_BACKUP"
            echo original=1 > "$SMART_CONFIG_STATE"
        else
            echo original=0 > "$SMART_CONFIG_STATE"
        fi
        chmod 0600 "$SMART_CONFIG_STATE" "$SMART_CONFIG_BACKUP" 2>/dev/null
    fi
    smart_tmp="$SMART_CONFIG_TARGET.plf110.$$"
    if cp -f "$OEM_CONFIG_SOURCE" "$smart_tmp"; then
        if grep -q '<config [^>]*maxrefreshsettings=' "$smart_tmp"; then
            sed -i 's/maxrefreshsettings="[0-9][0-9]*"/maxrefreshsettings="4"/' "$smart_tmp"
        else
            sed -i '/<config /s/<config /<config maxrefreshsettings="4" /' "$smart_tmp"
        fi
        if ! grep -q '<config [^>]*defaultMaxRate=' "$smart_tmp"; then
            sed -i '/<config /s/<config /<config defaultMaxRate="144" /' "$smart_tmp"
        else
            sed -i 's/defaultMaxRate="[0-9][0-9.]*"/defaultMaxRate="144"/' "$smart_tmp"
        fi
        if ! grep -q '<config [^>]*maxrefreshsettings="4"' "$smart_tmp" ||
                ! grep -q '<config [^>]*defaultMaxRate="144"' "$smart_tmp"; then
            rm -f "$smart_tmp"
            echo "[$(date '+%F %T')] OEM refresh config patch validation failed"
        elif [ -f "$SMART_CONFIG_TARGET" ] && cmp -s "$smart_tmp" "$SMART_CONFIG_TARGET"; then
            rm -f "$smart_tmp"
            echo "[$(date '+%F %T')] OEM-derived smart-144 config unchanged; skipped rewrite source_sha256=$source_hash"
        else
            chown 1000:1000 "$smart_tmp" 2>/dev/null
            chmod 0600 "$smart_tmp" 2>/dev/null
            chcon u:object_r:system_data_file:s0 "$smart_tmp" 2>/dev/null || restorecon "$smart_tmp" 2>/dev/null
            mv -f "$smart_tmp" "$SMART_CONFIG_TARGET"
            echo "[$(date '+%F %T')] installed OEM-derived ColorOS smart-144 config source_sha256=$source_hash"
        fi
    else
        rm -f "$smart_tmp"
        echo "[$(date '+%F %T')] failed to install smart-144 RUS config"
    fi
fi

if [ ! -d /sys/module/PLF110_Display_OC ]; then
    insmod "$MODDIR/PLF110_Display_OC.ko"
    echo "[$(date '+%F %T')] early insmod rc=$?"
else
    echo "[$(date '+%F %T')] early module already loaded"
fi

if [ ! -r /sys/module/PLF110_Display_OC/parameters/status ]; then
    echo "[$(date '+%F %T')] early status unavailable; late service will retry"
    exit 0
fi

# The LKM directly scans the already-bound 1420a000.dsi0 device. Normally the
# first attempt succeeds immediately; short retries cover a still-finishing DRM
# bind without holding Android's post-fs-data stage for long.
i=0
while [ "$i" -lt 4 ]; do
    status=$(cat /sys/module/PLF110_Display_OC/parameters/status 2>/dev/null)
    echo "[$(date '+%F %T')] early status $status"
    case "$status" in
        *installed=1*"modes=5"*"mtk_modes=5"*)
            echo "[$(date '+%F %T')] early injection already ready"
            exit 0
            ;;
        *captured=1*)
            echo 1 > /sys/module/PLF110_Display_OC/parameters/enable
            rc=$?
            status=$(cat /sys/module/PLF110_Display_OC/parameters/status 2>/dev/null)
            echo "[$(date '+%F %T')] early enable rc=$rc status $status"
            case "$status" in
                *installed=1*"modes=5"*"mtk_modes=5"*)
                    echo "[$(date '+%F %T')] early injection ready before HWC"
                    exit 0
                    ;;
            esac
            ;;
    esac
    i=$((i + 1))
    sleep 1
done

echo "[$(date '+%F %T')] early injection deferred to late service"
exit 0
