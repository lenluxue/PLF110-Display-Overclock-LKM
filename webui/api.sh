#!/system/bin/sh

STATE_DIR=/data/adb/plf110_display_oc
MODDIR=${0%/*}/..
BASE_TARGET=/data/system/refresh_rate_config.xml
POLICY_READER="$MODDIR/bin/plf110-policy-reader.dex"
OVERRIDE_TARGET=/data/system/refresh_rate_config_user_override.xml
MANAGED_FILE="$STATE_DIR/webui_app_rates.conf"
WEBUI_STATE="$STATE_DIR/webui_app_rates.state"
WEBUI_BACKUP="$STATE_DIR/refresh_rate_config_user_override.webui-backup.xml"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

valid_package() {
    case "$1" in
        ''|*[!A-Za-z0-9_.]*) return 1 ;;
        [A-Za-z0-9_]* ) return 0 ;;
        *) return 1 ;;
    esac
}

validate_xml() {
    [ -r "$1" ] || return 1
    awk '
        /^[[:space:]]*<map>[[:space:]]*$/ { opened++ }
        /^[[:space:]]*<\/map>[[:space:]]*$/ { closed++ }
        /<string name=/ && $0 !~ /^[[:space:]]*<string name="[^"]+">[^<]*<\/string>[[:space:]]*$/ { malformed = 1 }
        END { exit !(opened == 1 && closed == 1 && !malformed) }
    ' "$1"
}

validate_managed_file() {
    [ -r "$MANAGED_FILE" ] || return 0
    awk -F= '
        NR == 1 && $0 == "# PLF110 WebUI app rates v1" { header = 1; next }
        NR == 1 { bad = 1 }
        /^#/ { next }
        NF != 2 { bad = 1; next }
        $1 !~ /^[A-Za-z0-9_][A-Za-z0-9_.]*$/ { bad = 1; next }
        $2 !~ /^(auto|60|90|120|144)$/ { bad = 1; next }
        seen[$1]++ { bad = 1 }
        END { exit !(header && !bad) }
    ' "$MANAGED_FILE"
}

capture_backup() {
    [ -f "$WEBUI_STATE" ] && return 0
    mkdir -p "$STATE_DIR" || return 1
    if [ -f "$OVERRIDE_TARGET" ]; then
        cp -p "$OVERRIDE_TARGET" "$WEBUI_BACKUP" || return 1
        printf 'original=1\n' > "$WEBUI_STATE" || return 1
    else
        printf 'original=0\n' > "$WEBUI_STATE" || return 1
    fi
    chmod 0600 "$WEBUI_STATE" 2>/dev/null
    [ -f "$WEBUI_BACKUP" ] && chmod 0600 "$WEBUI_BACKUP" 2>/dev/null
    return 0
}

install_override() {
    install_file=$1
    chown 1000:1000 "$install_file" 2>/dev/null
    chmod 0600 "$install_file" 2>/dev/null
    chcon u:object_r:system_data_file:s0 "$install_file" 2>/dev/null || restorecon "$install_file" 2>/dev/null
    mv -f "$install_file" "$OVERRIDE_TARGET"
}

apply_managed_overrides() {
    [ -f "$MANAGED_FILE" ] || return 0
    validate_managed_file || return 1

    if [ -f "$OVERRIDE_TARGET" ]; then
        validate_xml "$OVERRIDE_TARGET" || return 1
        cp -f "$OVERRIDE_TARGET" "$OVERRIDE_TARGET.webui.$$" || return 1
    else
        mkdir -p "${OVERRIDE_TARGET%/*}" || return 1
        printf '%s\n' "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>" '<map>' '</map>' > "$OVERRIDE_TARGET.webui.$$" || return 1
    fi

    staged="$OVERRIDE_TARGET.webui.$$.next"
    if ! awk -F= -v config_file="$MANAGED_FILE" '
        FILENAME == config_file {
            if ($0 ~ /^#/) next
            package = $1
            rate = $2
            if (!(package in rates)) order[++count] = package
            rates[package] = rate
            next
        }
        {
            line = $0
            if (line ~ /<string name="[^"]+">[^<]*<\/string>/) {
                package = line
                sub(/^.*<string name="/, "", package)
                sub(/".*$/, "", package)
                if (package in rates) {
                    if (!seen[package]++) {
                        if (rates[package] != "auto") {
                            indent = line
                            sub(/[^ \t].*$/, "", indent)
                            if (rates[package] == "60") id = 2
                            else if (rates[package] == "90") id = 1
                            else if (rates[package] == "120") id = 3
                            else if (rates[package] == "144") id = 4
                            print indent "<string name=\"" package "\">0-0-0-" id "</string>"
                        }
                    }
                    next
                }
            }
            if (line ~ /<\/map>/) {
                for (i = 1; i <= count; i++) {
                    package = order[i]
                    if (package in seen || rates[package] == "auto") continue
                    if (rates[package] == "60") id = 2
                    else if (rates[package] == "90") id = 1
                    else if (rates[package] == "120") id = 3
                    else if (rates[package] == "144") id = 4
                    print "    <string name=\"" package "\">0-0-0-" id "</string>"
                }
            }
            print line
        }
    ' "$MANAGED_FILE" "$OVERRIDE_TARGET.webui.$$" > "$staged"; then
        rm -f "$staged" "$OVERRIDE_TARGET.webui.$$"
        return 1
    fi
    rm -f "$OVERRIDE_TARGET.webui.$$"
    validate_xml "$staged" || {
        rm -f "$staged"
        return 1
    }
    if cmp -s "$staged" "$OVERRIDE_TARGET"; then
        rm -f "$staged"
        return 0
    fi
    install_override "$staged"
}

list_default_policy() {
    # File rules are a labelled fallback/reference, not a live FPS reading.
    if [ -r "$BASE_TARGET" ]; then
        awk -v requested_list="$*" '
            function attr(text, name, value) {
                if (!match(text, "(^|[[:space:]])" name "[[:space:]]*=[[:space:]]*\"[^\"]*\"")) return ""
                value = substr(text, RSTART, RLENGTH)
                sub(/^[^=]*=[[:space:]]*"/, "", value)
                sub(/"$/, "", value)
                return value
            }
            BEGIN {
                RS = "<"
                count = split(requested_list, names, /[[:space:]]+/)
                for (i = 1; i <= count; i++) if (names[i] != "") requested[names[i]] = 1
                filtered = (requested_list != "")
            }
            /^config[[:space:]]/ {
                rate = attr($0, "defaultRateId")
                if (rate ~ /^[0-9]+(-[0-9]+)+$/) print "BASE_GLOBAL\t-\t" rate
            }
            /^item[[:space:]]/ {
                package = attr($0, "package"); rate = attr($0, "rateId")
                activity = attr($0, "activity")
                if (package !~ /^[A-Za-z0-9_][A-Za-z0-9_.]*$/ || rate !~ /^[0-9]+(-[0-9]+)+$/) next
                if (filtered && !(package in requested)) next
                if (activity == "") print "BASE\t" package "\t" rate
                else print "ACTIVITY\t" package "\t" rate
            }
        ' "$BASE_TARGET"
    fi
    choice=$(settings --user 0 get secure choice_mode_rate 2>/dev/null)
    case "$choice" in
        ''|*[!0-9]*) policy_mode=3 ;;
        *) if [ "$choice" -gt 120 ]; then policy_mode=8; else policy_mode=3; fi ;;
    esac
    printf 'INFO\tpolicy_mode=%s\n' "$policy_mode"
    classpath="$POLICY_READER"
    for jar in /system/framework/oplus-framework.jar /system_ext/framework/oplus-framework.jar; do
        [ -r "$jar" ] && classpath="$classpath:$jar"
    done
    if [ -r "$POLICY_READER" ] && command -v timeout >/dev/null 2>&1; then
        if result=$(CLASSPATH="$classpath" timeout 12 /system/bin/app_process /system/bin Plf110PolicyReader "$policy_mode" "$@" 2>/dev/null); then
            printf '%s\n' "$result"
            return 0
        fi
    fi
    printf 'INFO\tpolicy_backend=file\n'
}

list_config() {
    for requested in "$@"; do valid_package "$requested" || fail "应用包名无效"; done
    if [ -f "$OVERRIDE_TARGET" ]; then
        printf 'INFO\txml=1\n'
        awk '
            /<string name="[A-Za-z0-9_.][A-Za-z0-9_.]*">[0-9]+-[0-9]+-[0-9]+-[0-9]+<\/string>/ {
                line = $0
                sub(/^.*<string name="/, "", line)
                package = line
                sub(/">.*$/, "", package)
                sub(/^.*">/, "", line)
                sub(/<\/string>.*/, "", line)
                split(line, ids, "-")
                printf "XML\t%s\t%s\n", package, ids[4]
            }
        ' "$OVERRIDE_TARGET"
    else
        printf 'INFO\txml=0\n'
    fi
    if [ -f "$WEBUI_STATE" ]; then
        printf 'INFO\tbackup=1\n'
    else
        printf 'INFO\tbackup=0\n'
    fi
    if [ -f "$MANAGED_FILE" ]; then
        validate_managed_file || fail "保存的策略文件校验失败"
        awk -F= 'NR == 1 { next } /^#/ { next } NF == 2 { print "MANAGED\t" $1 "\t" $2 }' "$MANAGED_FILE"
    fi
    list_default_policy "$@"
}

set_config() {
    package=$1
    rate=$2
    valid_package "$package" || fail "应用包名无效"
    case "$rate" in
        auto|60|90|120|144) ;;
        *) fail "刷新率选项无效" ;;
    esac
    capture_backup || fail "无法创建修改前备份"
    validate_managed_file || fail "保存的策略文件校验失败"

    next="$MANAGED_FILE.tmp.$$"
    previous="$MANAGED_FILE.previous.$$"
    had_previous=0
    if [ -f "$MANAGED_FILE" ]; then
        cp -p "$MANAGED_FILE" "$previous" || fail "无法暂存旧策略"
        had_previous=1
    fi
    {
        printf '%s\n' '# PLF110 WebUI app rates v1'
        if [ -f "$MANAGED_FILE" ]; then
            awk -F= -v wanted="$package" -v value="$rate" '
                NR == 1 { next }
                /^#/ { next }
                $1 == wanted {
                    if (!replaced++) print wanted "=" value
                    next
                }
                NF == 2 { print $1 "=" $2 }
                END { if (!replaced) print wanted "=" value }
            ' "$MANAGED_FILE"
        else
            printf '%s=%s\n' "$package" "$rate"
        fi
    } > "$next" || fail "无法写入策略文件"
    chmod 0600 "$next" 2>/dev/null
    mv -f "$next" "$MANAGED_FILE" || fail "无法安装策略文件"
    if ! apply_managed_overrides; then
        if [ "$had_previous" = 1 ]; then
            mv -f "$previous" "$MANAGED_FILE"
        else
            rm -f "$previous" "$MANAGED_FILE"
        fi
        fail "应用覆盖 XML 校验失败，策略未保存"
    fi
    rm -f "$previous"
    printf 'OK\t已保存\n'
}

restore_config() {
    [ -f "$WEBUI_STATE" ] || fail "没有可恢复的 WebUI 备份"
    original=$(sed -n 's/^original=//p' "$WEBUI_STATE" | head -n 1)
    case "$original" in
        1)
            [ -r "$WEBUI_BACKUP" ] || fail "找不到修改前备份"
            restore_tmp="$OVERRIDE_TARGET.webui-restore.$$"
            cp -p "$WEBUI_BACKUP" "$restore_tmp" || fail "无法暂存备份"
            install_override "$restore_tmp"
            ;;
        0)
            rm -f "$OVERRIDE_TARGET"
            ;;
        *) fail "备份状态无效" ;;
    esac
    rm -f "$MANAGED_FILE"
    printf 'OK\t已恢复\n'
}

case "$1" in
    list) shift; list_config "$@" ;;
    set) [ "$#" -eq 3 ] || fail "参数无效"; set_config "$2" "$3" ;;
    restore) restore_config ;;
    boot-apply) apply_managed_overrides || fail "开机重放 WebUI 策略失败" ;;
    *) fail "未知命令" ;;
esac
