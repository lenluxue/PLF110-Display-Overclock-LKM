// SPDX-License-Identifier: GPL-2.0-only
/* Append to the ORIGINAL KO; never recompile its existing implementation. */
#define OPLUS_FEATURE_DISPLAY 1
#define OPLUS_FEATURE_DISPLAY_ADFR 1
#define OPLUS_FEATURE_DISPLAY_HPWM 1
#define OPLUS_FEATURE_DISPLAY_APOLLO 1
#define OPLUS_FEATURE_DISPLAY_ONSCREENFINGERPRINT 1
#define OPLUS_FEATURE_DISPLAY_TEMP_COMPENSATION 1
#define OPLUS_FEATURE_DISPLAY_MAINLINE 1
#define OPLUS_TRACKPOINT_REPORT 1
#define OPLUS_DISPLAY_FEATURE_DMR 1
#ifdef SYNC_UNIT_TEST
#include "sync_shim.h"
#else
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/kprobes.h>
#include <linux/ptrace.h>
#include <linux/sched.h>
#include <drm/drm_connector.h>
#include <drm/drm_modes.h>
#define DRM_CMDQ_DISABLE 1
#define MTK_DRM_CRTC_H
#define DSI_CMD_V2_SCN_NUM 6
struct mtk_drm_crtc;
#include "mtk_dsi.h"
/* Cross-checked against the original KO and this ROM's vendor DRM binary. */
static_assert(offsetof(struct mtk_dsi, ddp_comp) == 0);
static_assert(offsetof(struct mtk_dsi, conn) == 0x180);
static_assert(offsetof(struct mtk_dsi, ext) == 0x910);
static_assert(offsetof(struct mtk_panel_ext, funcs) == 0);
static_assert(offsetof(struct mtk_panel_ext, params) == 8);
static_assert(offsetof(struct mtk_panel_funcs, set_backlight_cmdq) == 0x10);
static_assert(offsetof(struct mtk_panel_funcs, hbm_get_state) == 0xe0);
static_assert(DSI_SET_BL == 38 && DSI_HBM_GET_STATE == 46);
#endif
#include "brightness_gain.h"

/* Only field zero of the verified original 67944-byte state is shared. */
struct plf_base_prefix { struct mtk_dsi *dsi; };
extern struct plf_base_prefix state;
extern int plf_original_vdo_update(struct drm_connector *, unsigned int, unsigned int);
extern int custom_slot_for_mode(const struct drm_display_mode *);

static struct kprobe phy_probe, ofp_probe;
static void *saved_phy_addr, *saved_ofp_addr;
static unsigned int sync_enabled;
/* gain x10 in bits 0..15, original LED request in 16..31, guard in bit 32. */
static u64 sync_control = PLF_GAIN_MAX | ((u64)1 << 32);
static unsigned int context_busy;
static struct task_struct *context_task;
static struct mtk_dsi *context_dsi;
static unsigned int context_target, context_request, context_gain;
static bool context_taken;
static unsigned long sync_queued, sync_skipped, sync_modes;
static unsigned int last_request, last_target;
static int sync_error;

static bool control_snapshot(unsigned int *gain, unsigned int *request)
{
    u64 packed = READ_ONCE(sync_control);
    *gain = packed & 0xffff;
    *request = (packed >> 16) & 0xffff;
    return !((packed >> 32) & 1) && *gain >= PLF_GAIN_MIN && *gain <= PLF_GAIN_MAX &&
        *request >= 2 && *request <= 3515;
}

/* This is a saved DIRECT vendor call, resolved by kprobes, not an arbitrary
 * callback. Its entry is probed again with context_taken=true, which resumes
 * the original instruction and avoids recursion. No work runs in pre_handler. */
static noinline __attribute__((no_sanitize("kcfi"))) void call_original_phy(
    struct mtk_dsi *dsi, struct cmdq_pkt *handle)
{
    typedef void (*phy_fn)(struct mtk_dsi *, struct cmdq_pkt *);
    ((phy_fn)saved_phy_addr)(dsi, handle);
}

/* Modern Oplus panels often have no generic panel hbm_get_state callback.
 * Resolve the native OFP getter rather than interpreting that missing callback
 * as HBM permanently on (which would silently disable every sync attempt). */
static noinline __attribute__((no_sanitize("kcfi"))) int call_ofp_hbm(void)
{
    typedef int (*ofp_fn)(void);
    return ((ofp_fn)saved_ofp_addr)();
}

static noinline void sync_phy_call(struct mtk_dsi *dsi, struct cmdq_pkt *handle)
{
    unsigned int gain, request, target = READ_ONCE(context_target);
    bool hbm = false;
    int ret = 0;
    if (handle && dsi && current == READ_ONCE(context_task) &&
        dsi == READ_ONCE(context_dsi) &&
        control_snapshot(&gain, &request) &&
        gain == READ_ONCE(context_gain) &&
        request == READ_ONCE(context_request) &&
        dsi->ext && dsi->ext->params && dsi->ext->funcs &&
        dsi->ext->funcs->set_backlight_cmdq &&
        !dsi->ext->params->vdo_mix_mode_en && call_ofp_hbm() == 0) {
        /* Original vendor io_cmd handles the real panel ABI and OFP filter.
         * Never call mtk_drm_setbacklight here: the CRTC lock is already held. */
        if (dsi->ext->funcs->hbm_get_state) {
            hbm = true; /* Fail closed if an advertised callback does not fill it. */
            ret = mtk_ddp_comp_io_cmd(&dsi->ddp_comp, handle,
                DSI_HBM_GET_STATE, &hbm);
        }
        if (ret >= 0 && !hbm) {
            ret = mtk_ddp_comp_io_cmd(&dsi->ddp_comp, handle,
                DSI_SET_BL, &target);
            if (ret >= 0) {
                WRITE_ONCE(last_request, request);
                WRITE_ONCE(last_target, target);
                sync_queued++;
            } else { sync_error = ret; sync_skipped++; }
        } else sync_skipped++;
    } else sync_skipped++;
    /* In the verified MIPI_HOP video path this point follows CMD_EOF and
     * precedes PHY timing, porch and PLL changes. The OEM backlight sender
     * waits/polls VM-command completion in this SAME packet; no separate
     * packet, video stop/start, raw MMIO, or CRTC lock acquisition is added. */
    call_original_phy(dsi, handle);
}

static int phy_pre_handler(struct kprobe *probe, struct pt_regs *regs)
{
    struct mtk_dsi *dsi = READ_ONCE(context_dsi);
    (void)probe;
    if (!READ_ONCE(sync_enabled) || READ_ONCE(context_task) != current ||
        READ_ONCE(context_taken) || !dsi ||
        regs->regs[0] != (unsigned long)dsi ||
        !regs->regs[1]) return 0;
    WRITE_ONCE(context_taken, true);
    instruction_pointer_set(regs, (unsigned long)sync_phy_call);
    return 1;
}

static struct drm_display_mode *mode_at(struct drm_connector *connector,
    unsigned int index)
{
    struct drm_display_mode *mode;
    unsigned int n = 0;
    list_for_each_entry(mode, &connector->modes, head) {
        if (n == index) return mode;
        if (++n > 31) break;
    }
    return NULL;
}

int plf_brightness_vdo_update(struct drm_connector *connector,
    unsigned int cur_mode, unsigned int dst_mode)
{
    struct mtk_dsi *dsi = READ_ONCE(state.dsi);
    struct drm_display_mode *cur, *dst;
    unsigned int gain, request, target;
    int ret;
    bool entering, exiting;
    if (!READ_ONCE(sync_enabled) || !dsi || !connector ||
        connector != &dsi->conn || cur_mode == dst_mode ||
        !control_snapshot(&gain, &request))
        return plf_original_vdo_update(connector, cur_mode, dst_mode);
    cur = mode_at(connector, cur_mode); dst = mode_at(connector, dst_mode);
    entering = dst && custom_slot_for_mode(dst) == 0;
    exiting = cur && custom_slot_for_mode(cur) == 0 && !entering;
    if ((!entering && !exiting) || cmpxchg(&context_busy, 0, 1) != 0)
        return plf_original_vdo_update(connector, cur_mode, dst_mode);
    if (!try_module_get(THIS_MODULE)) {
        WRITE_ONCE(context_busy, 0);
        return plf_original_vdo_update(connector, cur_mode, dst_mode);
    }
    target = entering ? plf_gain_target(request, gain) : request;
    if (target < 2) target = 2;
    WRITE_ONCE(context_dsi, dsi);
    WRITE_ONCE(context_request, request);
    WRITE_ONCE(context_gain, gain);
    WRITE_ONCE(context_target, target);
    WRITE_ONCE(context_taken, false);
    smp_wmb(); WRITE_ONCE(context_task, current);
    sync_modes++;
    ret = plf_original_vdo_update(connector, cur_mode, dst_mode);
    WRITE_ONCE(context_task, NULL); smp_wmb();
    WRITE_ONCE(context_busy, 0);
    module_put(THIS_MODULE);
    return ret;
}

static int parse_uint(const char **cursor, unsigned int *out)
{
    const char *p = *cursor;
    unsigned int value = 0, digits = 0;
    while (*p >= '0' && *p <= '9') {
        if (++digits > 5) return -EINVAL;
        value = value * 10 + (*p++ - '0');
    }
    if (!digits) return -EINVAL;
    *cursor = p; *out = value; return 0;
}
static bool at_end(const char *p)
{
    while (*p == ' ' || *p == '\t' || *p == '\r' || *p == '\n') p++;
    return !*p;
}
static int control_set(const char *p, const struct kernel_param *kp)
{
    unsigned int gain, request, guard;
    (void)kp;
    if (plf_parse_gain(&p, &gain) || *p++ != ':' ||
        parse_uint(&p, &request) || *p++ != ':' ||
        parse_uint(&p, &guard) || !at_end(p) ||
        request > 4095 || guard > 1) return -EINVAL;
    WRITE_ONCE(sync_control, (u64)gain | ((u64)request << 16) | ((u64)guard << 32));
    return 0;
}
static int control_get(char *buffer, const struct kernel_param *kp)
{
    u64 packed = READ_ONCE(sync_control);
    unsigned int gain = packed & 0xffff;
    (void)kp;
    if (gain % PLF_GAIN_SCALE)
        return scnprintf(buffer, PAGE_SIZE, "%u.%u:%u:%u\n", gain / PLF_GAIN_SCALE,
            gain % PLF_GAIN_SCALE, (unsigned int)((packed >> 16) & 0xffff),
            (unsigned int)((packed >> 32) & 1));
    return scnprintf(buffer, PAGE_SIZE, "%u:%u:%u\n", gain / PLF_GAIN_SCALE,
        (unsigned int)((packed >> 16) & 0xffff), (unsigned int)((packed >> 32) & 1));
}
static int sync_enable_set(const char *p, const struct kernel_param *kp)
{
    unsigned int enable;
    int ret;
    (void)kp;
    if (parse_uint(&p, &enable) || !at_end(p) || enable > 1) return -EINVAL;
    if (enable == READ_ONCE(sync_enabled)) return 0;
    if (enable) {
        /* The original exit path stays byte-identical. Hold an extra module
         * reference until these added probes are explicitly unregistered. */
        if (!try_module_get(THIS_MODULE)) return -ENODEV;
        memset(&ofp_probe, 0, sizeof(ofp_probe));
        ofp_probe.symbol_name = "oplus_ofp_get_hbm_state";
        ret = register_kprobe(&ofp_probe);
        if (ret) goto put_ref;
        if (saved_ofp_addr && saved_ofp_addr != (void *)ofp_probe.addr) {
            ret = -ESTALE; goto remove_ofp;
        }
        saved_ofp_addr = (void *)ofp_probe.addr;
        memset(&phy_probe, 0, sizeof(phy_probe));
        phy_probe.symbol_name = "mtk_dsi_phy_timconfig";
        phy_probe.pre_handler = phy_pre_handler;
        ret = register_kprobe(&phy_probe);
        if (ret) goto remove_ofp;
        if (saved_phy_addr && saved_phy_addr != (void *)phy_probe.addr) {
            unregister_kprobe(&phy_probe);
            ret = -ESTALE; goto remove_ofp;
        }
        saved_phy_addr = (void *)phy_probe.addr;
        WRITE_ONCE(sync_error, 0);
        WRITE_ONCE(sync_enabled, 1);
    } else {
        WRITE_ONCE(sync_enabled, 0);
        unregister_kprobe(&phy_probe);
        unregister_kprobe(&ofp_probe);
        module_put(THIS_MODULE);
    }
    return 0;
remove_ofp:
    unregister_kprobe(&ofp_probe);
put_ref:
    module_put(THIS_MODULE);
    WRITE_ONCE(sync_error, ret);
    return ret;
}
static int sync_enable_get(char *buffer, const struct kernel_param *kp)
{
    (void)kp;
    return scnprintf(buffer, PAGE_SIZE, "%u\n", READ_ONCE(sync_enabled));
}
static int sync_status_get(char *buffer, const struct kernel_param *kp)
{
    (void)kp;
    return scnprintf(buffer, PAGE_SIZE,
        "enabled=%u modes=%lu queued=%lu skipped=%lu request=%u target=%u error=%d gain_scale=10\n",
        READ_ONCE(sync_enabled), READ_ONCE(sync_modes), READ_ONCE(sync_queued),
        READ_ONCE(sync_skipped), READ_ONCE(last_request), READ_ONCE(last_target),
        READ_ONCE(sync_error));
}
static const struct kernel_param_ops control_ops = { .set=control_set, .get=control_get };
static const struct kernel_param_ops enable_ops = { .set=sync_enable_set, .get=sync_enable_get };
static const struct kernel_param_ops status_ops = { .get=sync_status_get };
module_param_cb(brightness_sync_control, &control_ops, NULL, 0600);
module_param_cb(brightness_sync_enable, &enable_ops, NULL, 0600);
module_param_cb(brightness_sync_status, &status_ops, NULL, 0400);
