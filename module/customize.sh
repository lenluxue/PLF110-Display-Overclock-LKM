#!/system/bin/sh

ui_print " "
ui_print "  PLF778·144"
ui_print "  酷安丛雨颜烬 × Codex"
ui_print " "

device=$(getprop ro.product.device)
model=$(getprop ro.product.model)
case "$device:$model" in
    PLF110:*|*:PLF110) ;;
    *)
        ui_print "! 此构建只支持 PLF110，当前设备：${device:-unknown} / ${model:-unknown}"
        abort "设备不匹配"
        ;;
esac

ui_print "- 设备校验通过：${model:-PLF110}"
ui_print "- 支持档位：60 / 90 / 120 / 144 Hz"
ui_print "- 刷新率调度将由 ColorOS 原生接管"
ui_print "- 安装完成后请重启设备"

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
