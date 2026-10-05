#!/system/bin/sh

MODDIR=${0%/*}
LOG=/data/adb/plf110_display_oc.log
LOG_LIMIT_BYTES=524288
STATE_DIR=/data/adb/plf110_display_oc
OEM_CONFIG_SOURCE=/my_product/etc/refresh_rate_config.xml
SMART_CONFIG_TARGET=/data/system/refresh_rate_config.xml
SMART_CONFIG_STATE="$STATE_DIR/refresh_config.state"
SMART_CONFIG_BACKUP="$STATE_DIR/refresh_rate_config.original.xml"
USER_OVERRIDE_TARGET=/data/system/refresh_rate_config_user_override.xml
USER_OVERRIDE_STATE="$STATE_DIR/refresh_rate_config_user_override.state"
USER_OVERRIDE_BACKUP="$STATE_DIR/refresh_rate_config_user_override.original.xml"
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

# --- 应用刷新率策略（设置 → 显示与亮度 → 自定义应用刷新率）-----------------
# rateId 的 4 个字段依次对应 auto / 90Hz / 60Hz / 120Hz 四档的偏好：
#   0=未指定  1=90Hz  2=60Hz  3=120Hz  4=144Hz（本模块注入的档位）
# 未被下面名单覆盖的应用走全局默认（3-1-2-3 = 120Hz）。
POLICY_DEFAULT_RATE_ID="3-1-2-3"
POLICY_VIDEO_RATE_ID="2-2-2-2"
POLICY_GAME_RATE_ID="4-1-2-3"
POLICY_VIDEO_PACKAGES="
com.ss.android.ugc.aweme
com.smile.gifmaker
com.kuaishou.nebula
com.ss.android.ugc.aweme.lite
com.ss.android.article.video
com.tencent.weishi
com.ss.android.ugc.live
com.baidu.haokan
com.kwai.thanos
tv.danmaku.bili
com.ss.android.ugc.trill
com.zhiliaoapp.musically.go
com.zhiliaoapp.musically
"
POLICY_GAME_PACKAGES="
com.tencent.tmgp.sgame
com.tencent.tmgp.sgamece
com.tencent.tmgp.pubgmhd
com.tencent.tmgp.pubgm
com.tencent.tmgp.dfm
com.tencent.tmgp.cf
com.tencent.tmgp.cfna
com.tencent.tmgp.cod
com.tencent.tmgp.codm
com.tencent.tmgp.speedmobile
com.tencent.tmgp.qqspeed
com.tencent.tmgp.bh3
com.tencent.tmgp.bh3oversea
com.tencent.tmgp.hyrz
com.tencent.tmgp.yys
com.tencent.tmgp.dpcq
com.tencent.tmgp.lol
com.tencent.tmgp.gnyx
com.tencent.tmgp.jj
com.tencent.tmgp.wows
com.tencent.tmgp.pes
com.tencent.tmgp.kof
com.tencent.tmgp.codev
com.miHoYo.Yuanshen
com.miHoYo.GenshinImpact
com.miHoYo.hkrpg
com.HoYoverse.hkrpgoversea
com.miHoYo.hkrpg.bilibili
com.miHoYo.bh3
com.miHoYo.bh3.bilibili
com.miHoYo.bh3oversea
com.miHoYo.Nap
com.miHoYo.nap
com.kurogame.mingchao
com.kurogame.mingchao.bilibili
com.kurogame.wutheringwaves.global
com.netease.hyxd
com.netease.dwrg
com.netease.l22
com.netease.g93na
com.netease.wxzc
com.netease.yys
com.netease.onmyoji
com.netease.mrzh
com.netease.nshm
com.netease.h75na
com.netease.racer
com.netease.lztgg
com.netease.chiji
com.netease.wotb
com.netease.party
com.netease.my
com.netease.stzb
com.netease.sky
com.netease.harrypotter
com.supercell.clashofclans
com.supercell.clashroyale
com.supercell.brawlstars
com.mojang.minecraftpe
com.roblox.client
com.activision.callofduty.shooter
com.garena.game.kgtw
com.garena.game.codm
com.mobile.legends
com.epicgames.fortnite
com.pubg.imobile
com.vng.pubgmobile
com.dts.freefireth
com.dts.freefiremax
com.lilithgame.hgame.cn
com.lilithgame.roc.gp
com.bilibili.azurlane
com.bilibili.fatego
com.bilibili.blhx
com.bilibili.priconne
com.yostar.arknights
com.hypergryph.arknights
com.xd.s2.gp
com.xd.dxl
com.xd.cfb
com.xd.t2
com.zy.wqmt.cn
com.netease.mkey
com.tencent.ig
com.tencent.tmgp.mf
com.tencent.tmgp.ssf
com.tencent.tmgp.ylm
com.tencent.tmgp.dft
com.tencent.tmgp.lj
com.tencent.tmgp.aq
com.tencent.tmgp.tmgp
com.tencent.tmgp.dfmexper
com.proxima.dfm
com.tencent.mf.uam
com.tencent.mf.uamty
com.proximabeta.mf.uamo
"
GAME_SECTION_START_PACKAGE="com.lilithgames.solarland.android.cn"
GAME_SECTION_END_PACKAGE="com.netease.qrsj.nearme.gamecenter"

GUARD_DIR="$STATE_DIR/boot-guard"
GUARD_PENDING="$GUARD_DIR/policy.pending"
GUARD_DISABLED="$STATE_DIR/policy.disabled"
GUARD_EVENTS="$GUARD_DIR/events.log"
CAPTURE_DIR=/data/local/tmp/plf110-capture
BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null | tr -cd '[:alnum:]-')
[ -n "$BOOT_ID" ] || BOOT_ID=unknown

guard_note() {
    mkdir -p "$GUARD_DIR" 2>/dev/null
    chmod 0700 "$GUARD_DIR" 2>/dev/null
    echo "[$(date '+%F %T')] boot=$BOOT_ID $*" >> "$GUARD_EVENTS" 2>/dev/null
}

# 万一再次卡屏，这里是唯一的取证手段：本轮开机的 logcat / 内核日志落盘。
start_boot_capture() {
    mkdir -p "$CAPTURE_DIR" 2>/dev/null
    chmod 0777 "$CAPTURE_DIR" 2>/dev/null
    timeout 900 logcat -b all -f "$CAPTURE_DIR/logcat-$BOOT_ID.log" -r 2048 -n 4 &
    timeout 900 dmesg -w > "$CAPTURE_DIR/dmesg-$BOOT_ID.log" 2>/dev/null &
}

install_config() {
    install_src=$1
    chown 1000:1000 "$install_src" 2>/dev/null
    chmod 0600 "$install_src" 2>/dev/null
    chcon u:object_r:system_data_file:s0 "$install_src" 2>/dev/null || restorecon "$install_src" 2>/dev/null
    mv -f "$install_src" "$SMART_CONFIG_TARGET"
}

patch_ceiling() {
    patch_file=$1
    if grep -q '<config [^>]*maxrefreshsettings=' "$patch_file"; then
        sed -i 's/maxrefreshsettings="[0-9][0-9]*"/maxrefreshsettings="4"/' "$patch_file"
    else
        sed -i '/<config /s/<config /<config maxrefreshsettings="4" /' "$patch_file"
    fi
    if grep -q '<config [^>]*defaultMaxRate=' "$patch_file"; then
        sed -i 's/defaultMaxRate="[0-9][0-9.]*"/defaultMaxRate="144"/' "$patch_file"
    else
        sed -i '/<config /s/<config /<config defaultMaxRate="144" /' "$patch_file"
    fi
    grep -q '<config [^>]*maxrefreshsettings="4"' "$patch_file" &&
        grep -q '<config [^>]*defaultMaxRate="144"' "$patch_file"
}

set_rate_id() {
    rate_file=$1
    rate_package=$2
    rate_value=$3
    grep -Fq "<item package=\"$rate_package\"" "$rate_file" || return 1
    rate_package_re=$(printf '%s' "$rate_package" | sed 's/\./\\./g')
    sed -i "/<item package=\"$rate_package_re\"/s/rateId=\"[^\"]*\"/rateId=\"$rate_value\"/" "$rate_file"
}

ensure_rate_id() {
    rate_file=$1
    rate_package=$2
    rate_value=$3
    if set_rate_id "$rate_file" "$rate_package" "$rate_value"; then
        return 0
    fi
    grep -q '</refresh_rate_config>' "$rate_file" || return 1
    rate_item="<item package=\"$rate_package\" rateId=\"$rate_value\" />"
    sed -i "/<\\/refresh_rate_config>/i\\  $rate_item" "$rate_file"
    grep -Fq "<item package=\"$rate_package\" rateId=\"$rate_value\"" "$rate_file"
}

# 在 OEM 配置副本上写入策略：其他应用 120Hz、短视频 60Hz、游戏 144Hz。
apply_app_rate_policy() {
    policy_file=$1
    policy_items_before=$(grep -c '<item package=' "$policy_file")

    if grep -q '<config [^>]*defaultRateId=' "$policy_file"; then
        sed -i "/<config /s/defaultRateId=\"[0-9-]*\"/defaultRateId=\"$POLICY_DEFAULT_RATE_ID\"/" "$policy_file"
    else
        sed -i "/<config /s/<config /<config defaultRateId=\"$POLICY_DEFAULT_RATE_ID\" /" "$policy_file"
    fi

    game_count=0
    game_start_line=$(grep -n "<item package=\"$GAME_SECTION_START_PACKAGE\"" "$policy_file" | head -n 1 | cut -d: -f1)
    game_end_line=$(grep -n "<item package=\"$GAME_SECTION_END_PACKAGE\"" "$policy_file" | tail -n 1 | cut -d: -f1)
    case "$game_start_line:$game_end_line" in
        ''|*:|:*)
            echo "[$(date '+%F %T')] OEM game block markers missing; using explicit package list"
            ;;
        *)
            sed -i "${game_start_line},${game_end_line}s/rateId=\"[^\"]*\"/rateId=\"$POLICY_GAME_RATE_ID\"/" "$policy_file"
            game_count=$(sed -n "${game_start_line},${game_end_line}p" "$policy_file" | grep -c '<item package=')
            ;;
    esac

    video_count=0
    for rate_package in $POLICY_VIDEO_PACKAGES; do
        if ensure_rate_id "$policy_file" "$rate_package" "$POLICY_VIDEO_RATE_ID"; then
            video_count=$((video_count + 1))
        fi
    done

    game_extra=0
    for rate_package in $POLICY_GAME_PACKAGES; do
        if ensure_rate_id "$policy_file" "$rate_package" "$POLICY_GAME_RATE_ID"; then
            game_extra=$((game_extra + 1))
        fi
    done

    [ "$(grep -c '<item package=' "$policy_file")" -ge "$policy_items_before" ] || return 1
    grep -q "defaultRateId=\"$POLICY_DEFAULT_RATE_ID\"" "$policy_file" || return 1
    grep -Eq 'rateId="[5-9]' "$policy_file" && return 1
    grep -Eq 'rateId="[0-9]-[0-9]-[0-9]-[0-9]"' "$policy_file" || return 1
    echo "[$(date '+%F %T')] policy applied default=$POLICY_DEFAULT_RATE_ID video_60=$video_count oem_game_144=$game_count extra_game_144=$game_extra"
    return 0
}

# A manual per-app choice is stored separately from refresh_rate_config.xml.
# ColorOS needs an explicit 144Hz choice for these games to expose the 144Hz
# option. Back up the file once and change only the generated game entries.
prepare_game_user_overrides() {
    policy_file=$1

    if [ ! -f "$USER_OVERRIDE_STATE" ]; then
        if [ -f "$USER_OVERRIDE_TARGET" ]; then
            cp -pf "$USER_OVERRIDE_TARGET" "$USER_OVERRIDE_BACKUP" || return 1
            echo original=1 > "$USER_OVERRIDE_STATE"
            chmod 0600 "$USER_OVERRIDE_BACKUP" 2>/dev/null
            echo "[$(date '+%F %T')] backed up user refresh overrides to $USER_OVERRIDE_BACKUP"
        else
            echo original=0 > "$USER_OVERRIDE_STATE"
            echo "[$(date '+%F %T')] user refresh override file absent; creating game defaults"
        fi
        chmod 0600 "$USER_OVERRIDE_STATE" 2>/dev/null
    fi

    game_override_tmp="$USER_OVERRIDE_TARGET.plf110.$$"
    if [ -f "$USER_OVERRIDE_TARGET" ]; then
        cp -f "$USER_OVERRIDE_TARGET" "$game_override_tmp" || return 1
    else
        mkdir -p "${USER_OVERRIDE_TARGET%/*}" 2>/dev/null
        printf '%s\n' "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>" '<map>' '</map>' > "$game_override_tmp" || return 1
    fi
    if ! grep -q '<map>' "$game_override_tmp" || ! grep -q '</map>' "$game_override_tmp"; then
        rm -f "$game_override_tmp" "$game_override_tmp.next"
        echo "[$(date '+%F %T')] user refresh override validation failed; kept original"
        return 1
    fi

    game_user_packages=
    game_start_line=$(grep -n "<item package=\"$GAME_SECTION_START_PACKAGE\"" "$policy_file" | head -n 1 | cut -d: -f1)
    game_end_line=$(grep -n "<item package=\"$GAME_SECTION_END_PACKAGE\"" "$policy_file" | tail -n 1 | cut -d: -f1)
    case "$game_start_line:$game_end_line" in
        ''|*:|:*)
            echo "[$(date '+%F %T')] game user override block markers missing; using explicit game list"
            ;;
        *)
            game_user_packages=$(sed -n "${game_start_line},${game_end_line}p" "$policy_file" |
                sed -n 's/.*<item package="\([^"]*\)".*/\1/p')
            ;;
    esac

    # Add the module's extra game packages, including packages absent from the
    # OEM game block. The policy pass above has already normalized them to 144.
    for rate_package in $POLICY_GAME_PACKAGES; do
        case " $game_user_packages " in
            *" $rate_package "*) ;;
            *) game_user_packages="$game_user_packages $rate_package" ;;
        esac
    done

    # Deduplicate the combined OEM and extra-game package list, then update
    # the XML in one awk pass. This runs during post-fs-data, so avoiding one
    # process per game keeps the boot path short.
    game_package_list="$STATE_DIR/game_user_override_packages.$$"
    printf '%s\n' "$game_user_packages" |
        awk '{ for (i = 1; i <= NF; i++) if (!seen[$i]++) print $i }' > "$game_package_list" || {
        rm -f "$game_package_list"
        return 1
    }
    game_override_count=$(wc -l < "$game_package_list" 2>/dev/null)
    case "$game_override_count" in
        ''|0|*[!0-9]*)
            rm -f "$game_package_list"
            echo "[$(date '+%F %T')] game user override package list is empty"
            return 1
            ;;
    esac

    normalized_tmp="$game_override_tmp.next"
    if ! awk '
        FNR == NR {
            if (NF && !wanted[$0]++) {
                order[++count] = $0
            }
            next
        }
        {
            line = $0
            if (match(line, /<string name="[^"]+"/)) {
                package_name = substr(line, RSTART, RLENGTH)
                sub(/^<string name="/, "", package_name)
                sub(/"$/, "", package_name)
                if (package_name in wanted) {
                    indent = line
                    sub(/[^ \t].*$/, "", indent)
                    print indent "<string name=\"" package_name "\">0-0-0-4</string>"
                    seen[package_name] = 1
                    next
                }
            }
            if (line ~ /<\/map>/) {
                for (i = 1; i <= count; i++) {
                    package_name = order[i]
                    if (!(package_name in seen)) {
                        print "    <string name=\"" package_name "\">0-0-0-4</string>"
                    }
                }
            }
            print line
        }
    ' "$game_package_list" "$game_override_tmp" > "$normalized_tmp"; then
        rm -f "$game_package_list" "$normalized_tmp" "$game_override_tmp"
        echo "[$(date '+%F %T')] game user override rewrite failed; kept original"
        return 1
    fi
    mv -f "$normalized_tmp" "$game_override_tmp"

    normalized_count=$(awk '
        FNR == NR {
            if (NF) wanted[$0] = 1
            next
        }
        {
            line = $0
            if (match(line, /<string name="[^"]+"/)) {
                package_name = substr(line, RSTART, RLENGTH)
                sub(/^<string name="/, "", package_name)
                sub(/"$/, "", package_name)
                if (package_name in wanted && line ~ />0-0-0-4<\/string>/) {
                    found[package_name] = 1
                }
            }
        }
        END {
            count = 0
            for (package_name in wanted) {
                if (package_name in found) count++
            }
            print count
        }
    ' "$game_package_list" "$game_override_tmp")
    rm -f "$game_package_list"
    if [ "$normalized_count" != "$game_override_count" ]; then
        rm -f "$game_override_tmp"
        echo "[$(date '+%F %T')] game user override validation failed expected=$game_override_count found=${normalized_count:-unknown}"
        return 1
    fi

    grep -q '<map>' "$game_override_tmp" && grep -q '</map>' "$game_override_tmp" || {
        rm -f "$game_override_tmp" "$game_override_tmp.next"
        echo "[$(date '+%F %T')] normalized user refresh override validation failed; kept original"
        return 1
    }

    if cmp -s "$game_override_tmp" "$USER_OVERRIDE_TARGET"; then
        rm -f "$game_override_tmp"
        echo "[$(date '+%F %T')] game user overrides already normalized game_144=$game_override_count"
    else
        chown 1000:1000 "$game_override_tmp" 2>/dev/null
        chmod 0600 "$game_override_tmp" 2>/dev/null
        chcon u:object_r:system_data_file:s0 "$game_override_tmp" 2>/dev/null || restorecon "$game_override_tmp" 2>/dev/null
        mv -f "$game_override_tmp" "$USER_OVERRIDE_TARGET"
        echo "[$(date '+%F %T')] normalized game user overrides game_144=$game_override_count"
    fi
}

start_boot_capture

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
# configuration every boot so ROM updates keep working. The ceiling is lifted to
# 4 settings / 144 Hz and the app rate policy is written onto that copy only.
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
    # 开机守卫：上次套用策略后没能开机完成，就回滚到基线并停用策略，
    # 直到用户删掉 /data/adb/plf110_display_oc/policy.disabled。
    policy_mode=apply
    if [ -f "$GUARD_DISABLED" ]; then
        policy_mode=disabled
        echo "[$(date '+%F %T')] app rate policy disabled by $GUARD_DISABLED; installing OEM baseline only"
    elif [ -f "$GUARD_PENDING" ]; then
        pending_boot=$(sed -n 's/^boot_id=//p' "$GUARD_PENDING" 2>/dev/null | head -n 1)
        if [ "$pending_boot" != "$BOOT_ID" ]; then
            policy_mode=rollback
            echo "[$(date '+%F %T')] previous boot=$pending_boot did not complete with the app rate policy; reverting to baseline and disabling policy"
            guard_note "rollback: boot=$pending_boot did not complete"
            rm -f "$GUARD_PENDING"
            printf 'reason=previous-boot-incomplete\nfailed_boot=%s\nrolled_back_at=%s\n' \
                "$pending_boot" "$(date '+%F %T')" > "$GUARD_DISABLED"
            chmod 0600 "$GUARD_DISABLED" 2>/dev/null
        fi
    fi

    smart_tmp="$SMART_CONFIG_TARGET.plf110.$$"
    transform_ok=0
    if cp -f "$OEM_CONFIG_SOURCE" "$smart_tmp"; then
        if patch_ceiling "$smart_tmp"; then
            if [ "$policy_mode" = apply ]; then
                if apply_app_rate_policy "$smart_tmp"; then
                    transform_ok=1
                else
                    echo "[$(date '+%F %T')] app rate policy validation failed; keeping existing config"
                fi
            else
                transform_ok=1
            fi
        else
            echo "[$(date '+%F %T')] ceiling patch validation failed; keeping existing config"
        fi
    else
        echo "[$(date '+%F %T')] failed to stage config candidate; keeping existing config"
    fi

    if [ "$transform_ok" -ne 1 ]; then
        rm -f "$smart_tmp"
    else
        candidate_hash=$(sha256sum "$smart_tmp" 2>/dev/null | awk '{print $1}')
        if [ -f "$SMART_CONFIG_TARGET" ] && cmp -s "$smart_tmp" "$SMART_CONFIG_TARGET"; then
            rm -f "$smart_tmp"
            echo "[$(date '+%F %T')] OEM-derived config unchanged; skipped rewrite policy_mode=$policy_mode sha256=$candidate_hash"
        else
            install_config "$smart_tmp"
            echo "[$(date '+%F %T')] installed OEM-derived config policy_mode=$policy_mode sha256=$candidate_hash source_sha256=$source_hash"
        fi
        if [ "$policy_mode" = apply ]; then
            mkdir -p "$GUARD_DIR" 2>/dev/null
            chmod 0700 "$GUARD_DIR" 2>/dev/null
            printf 'boot_id=%s\ncreated_at=%s\nconfig_sha256=%s\n' \
                "$BOOT_ID" "$(date '+%F %T')" "$candidate_hash" > "$GUARD_PENDING"
            chmod 0600 "$GUARD_PENDING" 2>/dev/null
            guard_note "policy armed for boot verification sha256=$candidate_hash"
        fi
    fi
    if [ "$policy_mode" = apply ] && [ -r "$SMART_CONFIG_TARGET" ]; then
        prepare_game_user_overrides "$SMART_CONFIG_TARGET"
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
