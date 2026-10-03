#!/system/bin/sh

STATE_DIR=/data/adb/plf110_display_oc
SMART_CONFIG_TARGET=/data/system/refresh_rate_config.xml
SMART_CONFIG_STATE="$STATE_DIR/refresh_config.state"
SMART_CONFIG_BACKUP="$STATE_DIR/refresh_rate_config.original.xml"
if grep -q '^original=1$' "$SMART_CONFIG_STATE" 2>/dev/null && [ -r "$SMART_CONFIG_BACKUP" ]; then
    cp -pf "$SMART_CONFIG_BACKUP" "$SMART_CONFIG_TARGET"
    chown 1000:1000 "$SMART_CONFIG_TARGET" 2>/dev/null
    chcon u:object_r:system_data_file:s0 "$SMART_CONFIG_TARGET" 2>/dev/null || restorecon "$SMART_CONFIG_TARGET" 2>/dev/null
elif grep -q '^original=0$' "$SMART_CONFIG_STATE" 2>/dev/null; then
    rm -f "$SMART_CONFIG_TARGET"
fi
rm -rf "$STATE_DIR"

echo "PLF110_Display_OC: uninstall takes effect after reboot; installed hooks are pinned for this boot." \
    >> /data/adb/plf110_display_oc.log
