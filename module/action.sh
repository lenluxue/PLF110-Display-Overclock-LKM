#!/system/bin/sh

# Action 仅输出模块与系统识别状态。

MODEL=$(getprop ro.product.model)
DEVICE=$(getprop ro.product.device)
MANUFACTURER=$(getprop ro.product.manufacturer)
ANDROID_VERSION=$(getprop ro.build.version.release)
COLOROS_VERSION=$(getprop ro.build.version.oplusrom)
BUILD_DISPLAY=$(getprop ro.build.display.id)
APP_MAX_SETTINGS=$(getprop ro.oplus.refreshrate.maxsettings)
MODULE_PROP=${0%/*}/module.prop
MODE_SOURCE_CACHE=/data/adb/plf110_display_oc/mode_source.cache
SETTINGS_144_FEATURE=/my_product/etc/permissions/oplus.product.display_features.xml

[ -n "$MODEL" ] || MODEL=unknown
[ -n "$DEVICE" ] || DEVICE=unknown
[ -n "$MANUFACTURER" ] || MANUFACTURER=unknown
[ -n "$ANDROID_VERSION" ] || ANDROID_VERSION=unknown
[ -n "$COLOROS_VERSION" ] || COLOROS_VERSION=unknown
[ -n "$BUILD_DISPLAY" ] || BUILD_DISPLAY=unknown
[ -n "$APP_MAX_SETTINGS" ] || APP_MAX_SETTINGS=unknown
MODULE_ID=$(sed -n 's/^id=//p' "$MODULE_PROP" 2>/dev/null | head -n 1)
MODULE_VERSION=$(sed -n 's/^version=//p' "$MODULE_PROP" 2>/dev/null | head -n 1)
[ -n "$MODULE_ID" ] || MODULE_ID=unknown
[ -n "$MODULE_VERSION" ] || MODULE_VERSION=unknown

kernel_144=0
framework_144=0
settings_app_144=0
grep -q '@144 ' /sys/module/PLF110_Display_OC/parameters/modes 2>/dev/null && kernel_144=1
dumpsys display 2>/dev/null | grep 'DisplayModeRecord{mMode=' | grep -q 'fps=144' && framework_144=1
grep -q 'oplus-feature name="oplus.software.performance.enable_high_refresh_rate"' "$SETTINGS_144_FEATURE" 2>/dev/null && settings_app_144=1

recognition_status() {
    case "$1:$2" in
        1:1) echo '已识别' ;;
        1:0) echo '部分识别' ;;
        0:1) echo '部分识别' ;;
        *) echo '未识别' ;;
    esac
}

echo "PLF110 显示信息"
echo "- 模块 ID：$MODULE_ID"
echo "- 模块版本：$MODULE_VERSION"
echo "- 具体型号：$MODEL"
echo "- 设备代号：$DEVICE"
echo "- 设备厂商：$MANUFACTURER"
echo "- ColorOS：$COLOROS_VERSION"
echo "- Android：$ANDROID_VERSION"
echo "- 系统构建：$BUILD_DISPLAY"
echo "- 144Hz 档位：$(recognition_status "$kernel_144" "$framework_144")"
echo "- 内核识别：$([ "$kernel_144" -eq 1 ] && echo present || echo missing)"
echo "- 系统识别：$([ "$framework_144" -eq 1 ] && echo present || echo missing)"
echo "- 应用自定义刷新率上限：$([ "$APP_MAX_SETTINGS" = 4 ] && echo '144Hz / ID 4' || echo "$APP_MAX_SETTINGS")"
echo "- 设置应用 144Hz 菜单：$([ "$settings_app_144" -eq 1 ] && echo ready || echo '等待重启生效')"
echo "- OEM 144Hz 配置 ID：$(sed -n 's/^source_144_id=//p' "$MODE_SOURCE_CACHE" 2>/dev/null | head -n 1)"
echo "- OEM 最大刷新率 ID：$(sed -n 's/^source_max_id=//p' "$MODE_SOURCE_CACHE" 2>/dev/null | head -n 1)"
