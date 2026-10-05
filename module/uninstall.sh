#!/system/bin/sh

STATE_DIR=/data/adb/plf110_display_oc
SMART_CONFIG_TARGET=/data/system/refresh_rate_config.xml
SMART_CONFIG_STATE="$STATE_DIR/refresh_config.state"
SMART_CONFIG_BACKUP="$STATE_DIR/refresh_rate_config.original.xml"
USER_OVERRIDE_TARGET=/data/system/refresh_rate_config_user_override.xml
USER_OVERRIDE_STATE="$STATE_DIR/refresh_rate_config_user_override.state"
USER_OVERRIDE_BACKUP="$STATE_DIR/refresh_rate_config_user_override.original.xml"
if grep -q '^original=1$' "$SMART_CONFIG_STATE" 2>/dev/null && [ -r "$SMART_CONFIG_BACKUP" ]; then
    cp -pf "$SMART_CONFIG_BACKUP" "$SMART_CONFIG_TARGET"
    chown 1000:1000 "$SMART_CONFIG_TARGET" 2>/dev/null
    chcon u:object_r:system_data_file:s0 "$SMART_CONFIG_TARGET" 2>/dev/null || restorecon "$SMART_CONFIG_TARGET" 2>/dev/null
elif grep -q '^original=0$' "$SMART_CONFIG_STATE" 2>/dev/null; then
    rm -f "$SMART_CONFIG_TARGET"
fi
if grep -q '^original=1$' "$USER_OVERRIDE_STATE" 2>/dev/null && [ -r "$USER_OVERRIDE_BACKUP" ]; then
    cp -pf "$USER_OVERRIDE_BACKUP" "$USER_OVERRIDE_TARGET"
    chown 1000:1000 "$USER_OVERRIDE_TARGET" 2>/dev/null
    chmod 0600 "$USER_OVERRIDE_TARGET" 2>/dev/null
    chcon u:object_r:system_data_file:s0 "$USER_OVERRIDE_TARGET" 2>/dev/null || restorecon "$USER_OVERRIDE_TARGET" 2>/dev/null
elif grep -q '^original=0$' "$USER_OVERRIDE_STATE" 2>/dev/null; then
    rm -f "$USER_OVERRIDE_TARGET"
fi
rm -rf "$STATE_DIR"

echo "PLF110_Display_OC: uninstall takes effect after reboot; installed hooks are pinned for this boot." \
    >> /data/adb/plf110_display_oc.log
