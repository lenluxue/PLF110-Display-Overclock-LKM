#!/system/bin/sh

ui_print " "
ui_print "  PLF110·144"
ui_print "  lenluxue"
ui_print " "

kernel_release=$(uname -r 2>/dev/null)
kernel_version=$(printf '%s\n' "$kernel_release" | sed -n 's/^\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
case "$kernel_version" in
    6.1.157|6.1.134|6.1.118|6.1.115) ;;
    *)
        ui_print "! 此构建只支持内核 6.1.157 / 6.1.134 / 6.1.118 / 6.1.115，当前内核：${kernel_release:-unknown}"
        abort "内核版本不匹配"
        ;;
esac


volume_key_choice() {
    local prompt="$1" timeout_seconds="${2:-10}" default="${3:-no}" key_event
    ui_print "$prompt（音量上键=是，音量下键=否，${timeout_seconds}秒超时）"
    if ! command -v getevent >/dev/null 2>&1 ||
       ! command -v timeout >/dev/null 2>&1; then
        ui_print "无法读取音量键，默认$default"
        [ "$default" = yes ] && return 0
        return 1
    fi

    # Only DOWN events count; a release from the preceding question is ignored.
    key_event=$(timeout "$timeout_seconds" getevent -ql 2>/dev/null |
        grep -m1 -E 'EV_KEY[[:space:]]+KEY_VOLUME(UP|DOWN)[[:space:]]+DOWN([[:space:]]|$)')
    case "$key_event" in
        *KEY_VOLUMEUP*) ui_print "用户选择是"; return 0 ;;
        *KEY_VOLUMEDOWN*) ui_print "用户选择否"; return 1 ;;
        *)
            ui_print "等待超时，默认$default"
            [ "$default" = yes ] && return 0
            return 1
            ;;
    esac
}


if ! volume_key_choice "确定安装吗？？" 10 no; then
    abort "已取消安装"
fi

ui_print "- 内核校验通过：${kernel_version:-unknown}（${kernel_release:-unknown}）"
ui_print "- 支持档位：60 / 90 / 120 / 144 Hz"
ui_print "- 刷新率调度将由 ColorOS 原生接管"


set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755
set_perm "$MODPATH/bin/plf110-brightness-comp" 0 0 0755
