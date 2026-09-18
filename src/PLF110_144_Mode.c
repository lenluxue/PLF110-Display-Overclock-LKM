// SPDX-License-Identifier: GPL-2.0-only
/*
 * PLF110 AA600 runtime 144 Hz mode injection.
 *
 * The project layout and several defensive ABI/KCFI validation ideas are
 * derived from MTK-Display-Overclock-LKM by Yunnijian.  Its PMB110 reference
 * source credits Smartisan_Apple_Kt.  Thank you both for publishing a useful
 * GPL reference for the MTK display community.
 *
 * PLF110 adaptation: 酷安丛雨颜烬 × OpenAI Codex.
 */

#define OPLUS_FEATURE_DISPLAY 1
#define OPLUS_FEATURE_DISPLAY_ADFR 1
#define OPLUS_FEATURE_DISPLAY_HPWM 1
#define OPLUS_FEATURE_DISPLAY_APOLLO 1
#define OPLUS_FEATURE_DISPLAY_ONSCREENFINGERPRINT 1
#define OPLUS_FEATURE_DISPLAY_TEMP_COMPENSATION 1
#define OPLUS_FEATURE_DISPLAY_MAINLINE 1
#define OPLUS_TRACKPOINT_REPORT 1
#define OPLUS_DISPLAY_FEATURE_DMR 1

#include <drm/drm_connector.h>
#include <drm/drm_device.h>
#include <drm/drm_mipi_dsi.h>
#include <drm/drm_modes.h>
#include <drm/drm_panel.h>
#include <drm/drm_probe_helper.h>
#include <linux/device.h>
#include <linux/errno.h>
#include <linux/kernel.h>
#include <linux/kprobes.h>
#include <linux/list.h>
#include <linux/module.h>
#include <linux/moduleparam.h>
#include <linux/mutex.h>
#include <linux/platform_device.h>
#include <linux/ptrace.h>
#include <linux/string.h>
#include <linux/uaccess.h>

#define DRM_CMDQ_DISABLE 1
/* Only the pointer ABI is needed here; avoid pulling the complete CRTC body. */
#define MTK_DRM_CRTC_H
#define DSI_CMD_V2_SCN_NUM 6
struct mtk_drm_crtc;
#include "mtk_dsi.h"

#define PLF110_VERMAGIC \
	"6.1.157-android14-11-o-gc2dad16af736 " \
	"SMP preempt mod_unload modversions aarch64"

#define PLF110_PANEL_DRIVER "aa600_p_3_a0025_vdo_panel"
#define PLF110_PRIMARY_DSI "1420a000.dsi0"

#define PLF110_STOCK_MODES 4
#define PLF110_TOTAL_MODES 5
#define PLF110_STOCK_60 0
#define PLF110_STOCK_90 1
#define PLF110_STOCK_120 2
#define PLF110_STOCK_30 3
#define PLF110_CUSTOM_144 4

#define PLF110_BASE_PLL_CLK 581
#define PLF110_BASE_DATA_RATE 1162
#define PLF110_144_DATA_RATE 1395

typedef int (*plf110_panel_get_modes_t)(struct drm_panel *panel,
	struct drm_connector *connector);
typedef int (*plf110_connector_fill_modes_t)(struct drm_connector *connector,
	u32 max_width, u32 max_height);
typedef int (*plf110_ext_param_set_t)(struct drm_panel *panel,
	struct drm_connector *connector, unsigned int mode);
typedef int (*plf110_ext_param_get_t)(struct drm_panel *panel,
	struct drm_connector *connector, struct mtk_panel_params **params,
	unsigned int mode);
typedef int (*plf110_vdo_update_t)(struct drm_connector *connector,
	unsigned int cur_mode, unsigned int dst_mode);

struct plf110_scan_result {
	struct drm_display_mode *stock[PLF110_STOCK_MODES];
	struct drm_display_mode *custom;
	unsigned int count;
	unsigned int stock_count;
	unsigned int custom_count;
};

struct plf110_state {
	struct mtk_dsi *dsi;

	struct mtk_panel_funcs *original_ext_funcs;
	plf110_ext_param_set_t original_ext_set;
	plf110_ext_param_get_t original_ext_get;
	plf110_vdo_update_t original_vdo_update;

	const struct drm_panel_funcs *original_panel_funcs;
	plf110_panel_get_modes_t original_panel_get_modes;
	const struct drm_connector_funcs *original_connector_funcs;
	plf110_connector_fill_modes_t original_connector_fill_modes;

	struct drm_panel_funcs hooked_panel_funcs;
	struct drm_connector_funcs hooked_connector_funcs;
	struct drm_display_mode custom_mode;
	struct mtk_panel_params custom_ext;

	struct kprobe panel_probe;
	struct kprobe porch_probe;
	bool panel_probe_registered;
	bool porch_probe_registered;
	bool installed;
	bool self_ref;
	bool refreshing;
	bool panel_hooked;
	bool connector_hooked;
	bool ext_hooked;

	unsigned long captures;
	unsigned long panel_enums;
	unsigned long injected;
	unsigned long fill_calls;
	unsigned long rebuilds;
	unsigned long hotplugs;
	unsigned long validation_failures;
	unsigned long ext_gets;
	unsigned long ext_sets;
	unsigned long mode_switches;
	unsigned long clock_attempts;
	unsigned long clock_switches;
	unsigned int stage;
	int last_rebuild_error;
	int last_error;
};

static struct plf110_state state;
static DEFINE_MUTEX(control_lock);

static noinline __used int plf110_panel_get_modes(
	struct drm_panel *panel, struct drm_connector *connector);
static noinline __used int plf110_connector_fill_modes(
	struct drm_connector *connector, u32 max_width, u32 max_height);
static noinline __used int plf110_ext_param_set(
	struct drm_panel *panel, struct drm_connector *connector,
	unsigned int mode);
static noinline __used int plf110_ext_param_get(
	struct drm_panel *panel, struct drm_connector *connector,
	struct mtk_panel_params **params, unsigned int mode);
static noinline __used int plf110_mode_switch_update_for_vdo(
	struct drm_connector *connector, unsigned int cur_mode,
	unsigned int dst_mode);

static unsigned int mode_refresh(const struct drm_display_mode *mode)
{
	u64 pixels;

	if (!mode || mode->clock <= 0 || !mode->htotal || !mode->vtotal)
		return 0;
	pixels = (u64)mode->htotal * mode->vtotal;
	return (unsigned int)(((u64)mode->clock * 1000ULL + pixels / 2) /
		pixels);
}

static bool mode_matches(const struct drm_display_mode *mode, int clock,
	u16 hdisplay, u16 hsync_start, u16 hsync_end, u16 htotal,
	u16 vdisplay, u16 vsync_start, u16 vsync_end, u16 vtotal)
{
	return mode && mode->clock == clock &&
		mode->hdisplay == hdisplay &&
		mode->hsync_start == hsync_start &&
		mode->hsync_end == hsync_end &&
		mode->htotal == htotal &&
		mode->vdisplay == vdisplay &&
		mode->vsync_start == vsync_start &&
		mode->vsync_end == vsync_end &&
		mode->vtotal == vtotal && mode->hskew == 0;
}

static int stock_slot_for_mode(const struct drm_display_mode *mode)
{
	if (mode_matches(mode, 387072, 1080, 1260, 1264, 1280,
		2392, 4984, 4986, 5040))
		return PLF110_STOCK_60;
	if (mode_matches(mode, 387072, 1080, 1260, 1264, 1280,
		2392, 3304, 3306, 3360))
		return PLF110_STOCK_90;
	if (mode_matches(mode, 387072, 1080, 1260, 1264, 1280,
		2392, 2464, 2466, 2520))
		return PLF110_STOCK_120;
	if (mode_matches(mode, 241920, 1080, 3180, 3184, 3200,
		2392, 2464, 2466, 2520))
		return PLF110_STOCK_30;
	return -EINVAL;
}

static int custom_slot_for_mode(const struct drm_display_mode *mode)
{
	return mode_matches(mode, 464486, 1080, 1209, 1213, 1229,
		2392, 2569, 2571, 2625) ? 0 : -EINVAL;
}

static struct drm_display_mode *mode_by_index(
	struct drm_connector *connector, unsigned int wanted)
{
	struct drm_display_mode *mode;
	unsigned int index = 0;

	if (!connector)
		return NULL;
	list_for_each_entry(mode, &connector->modes, head) {
		if (index++ == wanted)
			return mode;
		if (index > 32)
			break;
	}
	return NULL;
}

static int index_for_stock_slot(struct drm_connector *connector, int slot)
{
	struct drm_display_mode *mode;
	unsigned int index = 0;

	list_for_each_entry(mode, &connector->modes, head) {
		if (stock_slot_for_mode(mode) == slot)
			return (int)index;
		if (++index > 31)
			break;
	}
	return -ENOENT;
}

static int scan_connector_locked(struct drm_connector *connector,
	struct plf110_scan_result *result)
{
	struct drm_display_mode *mode;

	memset(result, 0, sizeof(*result));
	list_for_each_entry(mode, &connector->modes, head) {
		int slot;

		if (++result->count > 32)
			return -E2BIG;
		slot = stock_slot_for_mode(mode);
		if (slot >= 0) {
			if (result->stock[slot])
				return -EEXIST;
			result->stock[slot] = mode;
			result->stock_count++;
			continue;
		}
		if (custom_slot_for_mode(mode) == 0) {
			if (result->custom)
				return -EEXIST;
			result->custom = mode;
			result->custom_count++;
			continue;
		}
		return -ESTALE;
	}
	return 0;
}

static int validate_connector_locked(struct drm_connector *connector,
	bool installed, struct plf110_scan_result *result)
{
	int ret = scan_connector_locked(connector, result);
	int i;

	if (ret)
		goto failed;
	for (i = 0; i < PLF110_STOCK_MODES; i++) {
		if (!result->stock[i]) {
			ret = -ENOENT;
			goto failed;
		}
	}
	if (result->stock_count != PLF110_STOCK_MODES ||
		result->count != (installed ? PLF110_TOTAL_MODES :
			PLF110_STOCK_MODES) ||
		result->custom_count != (installed ? 1U : 0U)) {
		ret = -EINVAL;
		goto failed;
	}
	return 0;

failed:
	state.validation_failures++;
	return ret;
}

static int read_kcfi_type(const void *function, u32 *type_id)
{
	if (!function || (unsigned long)function < PAGE_SIZE)
		return -EINVAL;
	return copy_from_kernel_nofault(type_id,
		(void *)((unsigned long)function - sizeof(*type_id)),
		sizeof(*type_id)) ? -EFAULT : 0;
}

static int validate_kcfi(const void *live, const void *local)
{
	u32 live_type;
	u32 local_type;

	if (read_kcfi_type(live, &live_type) ||
		read_kcfi_type(local, &local_type))
		return -EFAULT;
	return live_type == local_type ? 0 : -EINVAL;
}

static bool panel_name_matches(struct drm_panel *panel)
{
	const char *name;

	if (!panel || !panel->dev || !panel->dev->driver)
		return false;
	name = panel->dev->driver->name;
	return name && strcmp(name, PLF110_PANEL_DRIVER) == 0;
}

static int capture_dsi(struct mtk_dsi *dsi, const char *source)
{
	if (!dsi || !dsi->panel || !panel_name_matches(dsi->panel) ||
		!dsi->conn.dev || !dsi->ext || !dsi->ext->funcs)
		return -ENODEV;

	if (cmpxchg(&state.dsi, NULL, dsi) == NULL) {
		state.captures++;
		pr_info("plf110_144_mode: captured primary DSI from %s\n",
			source ? source : "unknown");
	}
	return READ_ONCE(state.dsi) == dsi ? 0 : -EBUSY;
}

static int panel_pre_handler(struct kprobe *probe, struct pt_regs *regs)
{
	struct drm_panel *panel = (struct drm_panel *)regs->regs[0];
	struct mipi_dsi_device *device;
	struct mtk_dsi *dsi;

	(void)probe;
	if (READ_ONCE(state.dsi) || !panel_name_matches(panel))
		return 0;
	device = to_mipi_dsi_device(panel->dev);
	if (!device || !device->host)
		return 0;
	dsi = container_of(device->host, struct mtk_dsi, host);
	capture_dsi(dsi, "panel enumeration");
	return 0;
}

static int porch_pre_handler(struct kprobe *probe, struct pt_regs *regs)
{
	struct mtk_ddp_comp *comp = (struct mtk_ddp_comp *)regs->regs[0];
	struct mtk_dsi *dsi;

	(void)probe;
	if (!comp || READ_ONCE(state.dsi))
		return 0;
	dsi = container_of(comp, struct mtk_dsi, ddp_comp);
	capture_dsi(dsi, "porch update");
	return 0;
}

static int match_primary_dsi(struct device *dev, const void *data)
{
	const char *name = data;

	return dev && name && strcmp(dev_name(dev), name) == 0;
}

static int call_dsi_io(enum mtk_ddp_io_cmd command, void *params)
{
	struct mtk_dsi *dsi = READ_ONCE(state.dsi);

	if (!dsi || !dsi->ddp_comp.funcs ||
		!dsi->ddp_comp.funcs->io_cmd || dsi->ddp_comp.blank_mode)
		return -ENODEV;
	return mtk_ddp_comp_io_cmd(&dsi->ddp_comp, NULL, command, params);
}

static int rebuild_driver_modes(void)
{
	struct mtk_dsi *dsi = READ_ONCE(state.dsi);
	int ret;

	if (!dsi || !dsi->ddp_comp.mtk_crtc)
		return -ENODEV;
	ret = call_dsi_io(DSI_SET_CRTC_AVAIL_MODES,
		dsi->ddp_comp.mtk_crtc);
	if (ret < 0)
		return ret;
	ret = call_dsi_io(DSI_SET_CRTC_SCALING_MODE_MAPPING,
		dsi->ddp_comp.mtk_crtc);
	if (ret < 0)
		return ret;
	ret = call_dsi_io(DSI_FILL_CONNECTOR_PROP_CAPS,
		dsi->ddp_comp.mtk_crtc);
	if (ret < 0)
		return ret;
	state.rebuilds++;
	return 0;
}

static bool dyn_mipi_is_stock(const struct dynamic_mipi_params *dyn)
{
	return dyn->switch_en == 0 && dyn->pll_clk == 0 &&
		dyn->data_rate == 0 && dyn->data_rate_khz == 0 &&
		dyn->vsa == 0 && dyn->vbp == 0 && dyn->vfp == 0 &&
		dyn->vfp_lp_dyn == 0 && dyn->hsa == 0 &&
		dyn->hbp == 0 && dyn->hfp == 0 &&
		dyn->max_vfp_for_msync_dyn == 0;
}

static int prepare_custom_modes_locked(void)
{
	struct drm_connector *connector = &state.dsi->conn;
	struct drm_display_mode *stock120 = NULL;
	struct mtk_panel_params *base = NULL;
	struct drm_display_mode *mode;
	int index = 0;
	int stock_index = -1;
	int ret;

	list_for_each_entry(mode, &connector->modes, head) {
		if (stock_slot_for_mode(mode) == PLF110_STOCK_120) {
			stock120 = mode;
			stock_index = index;
			break;
		}
		if (++index > 31)
			break;
	}
	if (!stock120 || stock_index < 0 || !state.original_ext_get)
		return -ENODEV;

	ret = state.original_ext_get(state.dsi->panel, connector,
		&base, stock_index);
	if (ret || !base)
		return ret ? ret : -ENODEV;
	if (base->pll_clk != PLF110_BASE_PLL_CLK ||
		base->data_rate != PLF110_BASE_DATA_RATE ||
		!dyn_mipi_is_stock(&base->dyn) ||
		!base->dyn_fps.switch_en ||
		base->dyn_fps.vact_timing_fps != 120)
		return -ESTALE;

	memcpy(&state.custom_mode, stock120, sizeof(state.custom_mode));
	INIT_LIST_HEAD(&state.custom_mode.head);
	state.custom_mode.clock = 464486;
	state.custom_mode.hdisplay = 1080;
	state.custom_mode.hsync_start = 1209;
	state.custom_mode.hsync_end = 1213;
	state.custom_mode.htotal = 1229;
	state.custom_mode.vdisplay = 2392;
	state.custom_mode.vsync_start = 2569;
	state.custom_mode.vsync_end = 2571;
	state.custom_mode.vtotal = 2625;
	state.custom_mode.hskew = 0;
	state.custom_mode.type = DRM_MODE_TYPE_DRIVER;
	drm_mode_set_name(&state.custom_mode);

	memcpy(&state.custom_ext, base, sizeof(state.custom_ext));
	state.custom_ext.dyn.switch_en = 1;
	state.custom_ext.dyn.pll_clk = 0;
	state.custom_ext.dyn.data_rate = PLF110_144_DATA_RATE;
	state.custom_ext.dyn.data_rate_khz = 0;
	state.custom_ext.dyn.vsa = 2;
	state.custom_ext.dyn.vbp = 54;
	state.custom_ext.dyn.vfp = 177;
	state.custom_ext.dyn.vfp_lp_dyn = 0;
	state.custom_ext.dyn.hsa = 4;
	state.custom_ext.dyn.hbp = 16;
	state.custom_ext.dyn.hfp = 129;
	state.custom_ext.dyn.max_vfp_for_msync_dyn = 0;
	state.custom_ext.dyn_fps.vact_timing_fps = 144;
	state.custom_ext.dyn_fps.data_rate = 0;
	state.custom_ext.dyn_fps.data_rate_khz = 0;

	return custom_slot_for_mode(&state.custom_mode) == 0 ? 0 : -ERANGE;
}

static int switch_link(bool enable)
{
	struct mtk_dsi *dsi = READ_ONCE(state.dsi);
	u32 expected = enable ? PLF110_144_DATA_RATE :
		PLF110_BASE_DATA_RATE;
	int hopping = enable ? 1 : 0;
	int ret;

	if (!dsi || !dsi->ext || !dsi->ext->params)
		return -ENODEV;
	state.clock_attempts++;
	ret = call_dsi_io(MIPI_HOPPING, &hopping);
	if (ret < 0)
		return ret;
	if (!!READ_ONCE(dsi->mipi_hopping_sta) != enable ||
		READ_ONCE(dsi->data_rate) != expected)
		return -EIO;
	if (dsi->slave_dsi && READ_ONCE(dsi->slave_dsi->data_rate) != expected)
		return -EIO;
	state.clock_switches++;
	return 0;
}

static noinline __used int plf110_mode_switch_update_for_vdo(
	struct drm_connector *connector, unsigned int cur_mode,
	unsigned int dst_mode)
{
	struct drm_display_mode *cur;
	struct drm_display_mode *dst;
	struct mtk_panel_params *saved;
	bool cur_custom;
	bool dst_custom;
	int ret = 0;

	if (!connector || cur_mode == dst_mode || !READ_ONCE(state.installed) ||
		connector != &state.dsi->conn)
		return 0;
	cur = mode_by_index(connector, cur_mode);
	dst = mode_by_index(connector, dst_mode);
	if (!cur || !dst)
		return -EINVAL;
	cur_custom = custom_slot_for_mode(cur) == 0;
	dst_custom = custom_slot_for_mode(dst) == 0;
	state.mode_switches++;

	if (dst_custom) {
		if (!state.dsi->ext ||
			READ_ONCE(state.dsi->ext->params) != &state.custom_ext)
			return -ESTALE;
		ret = switch_link(true);
	} else if (cur_custom) {
		if (!state.dsi->ext)
			return -ENODEV;
		saved = READ_ONCE(state.dsi->ext->params);
		WRITE_ONCE(state.dsi->ext->params, &state.custom_ext);
		ret = switch_link(false);
		WRITE_ONCE(state.dsi->ext->params, saved);
	}
	if (ret)
		pr_err("plf110_144_mode: link switch %uHz->%uHz failed: %d\n",
			mode_refresh(cur), mode_refresh(dst), ret);
	state.last_error = ret;
	return ret;
}

static noinline __used int plf110_ext_param_set(
	struct drm_panel *panel, struct drm_connector *connector,
	unsigned int mode_index)
{
	struct drm_display_mode *mode = mode_by_index(connector, mode_index);
	int stock120_index;
	int ret;

	state.ext_sets++;
	if (!mode || custom_slot_for_mode(mode) != 0)
		return state.original_ext_set ?
			state.original_ext_set(panel, connector, mode_index) :
			-EOPNOTSUPP;
	if (!READ_ONCE(state.installed) || panel != state.dsi->panel ||
		connector != &state.dsi->conn || !state.original_ext_set)
		return -ESTALE;
	stock120_index = index_for_stock_slot(connector, PLF110_STOCK_120);
	if (stock120_index < 0)
		return stock120_index;
	ret = state.original_ext_set(panel, connector, stock120_index);
	if (!ret)
		WRITE_ONCE(state.dsi->ext->params, &state.custom_ext);
	return ret;
}

static noinline __used int plf110_ext_param_get(
	struct drm_panel *panel, struct drm_connector *connector,
	struct mtk_panel_params **params, unsigned int mode_index)
{
	struct drm_display_mode *mode = mode_by_index(connector, mode_index);
	struct mtk_panel_params *base = NULL;
	int stock120_index;
	int ret;

	state.ext_gets++;
	if (!mode || custom_slot_for_mode(mode) != 0)
		return state.original_ext_get ?
			state.original_ext_get(panel, connector, params, mode_index) :
			-EOPNOTSUPP;
	if (!READ_ONCE(state.installed) || !params ||
		panel != state.dsi->panel || connector != &state.dsi->conn ||
		!state.original_ext_get)
		return -ESTALE;
	stock120_index = index_for_stock_slot(connector, PLF110_STOCK_120);
	if (stock120_index < 0)
		return stock120_index;
	ret = state.original_ext_get(panel, connector, &base, stock120_index);
	if (!ret && base)
		*params = &state.custom_ext;
	return ret;
}

static bool custom_in_list(struct list_head *head)
{
	struct drm_display_mode *mode;

	list_for_each_entry(mode, head, head) {
		if (custom_slot_for_mode(mode) == 0)
			return true;
	}
	return false;
}

static noinline __used int plf110_panel_get_modes(
	struct drm_panel *panel, struct drm_connector *connector)
{
	struct drm_display_mode *mode;
	int ret;

	if (!state.original_panel_get_modes)
		return -ESTALE;
	ret = state.original_panel_get_modes(panel, connector);
	state.panel_enums++;
	if (ret < 0 || !READ_ONCE(state.installed) ||
		panel != state.dsi->panel || connector != &state.dsi->conn ||
		custom_in_list(&connector->probed_modes))
		return ret;

	mode = drm_mode_duplicate(connector->dev, &state.custom_mode);
	if (!mode) {
		state.last_error = -ENOMEM;
		return ret;
	}
	mode->type = DRM_MODE_TYPE_DRIVER;
	drm_mode_set_name(mode);
	drm_mode_probed_add(connector, mode);
	state.injected++;
	return ret + 1;
}

static void move_slot_to_tail(struct drm_connector *connector, int slot)
{
	struct drm_display_mode *mode;
	struct drm_display_mode *tmp;

	list_for_each_entry_safe(mode, tmp, &connector->modes, head) {
		if ((slot < PLF110_STOCK_MODES &&
			stock_slot_for_mode(mode) == slot) ||
			(slot == PLF110_CUSTOM_144 &&
			 custom_slot_for_mode(mode) == 0)) {
			list_move_tail(&mode->head, &connector->modes);
			return;
		}
	}
}

static noinline __used int plf110_connector_fill_modes(
	struct drm_connector *connector, u32 max_width, u32 max_height)
{
	struct plf110_scan_result scan;
	int ret;
	int validation;
	int slot;

	if (!state.original_connector_fill_modes)
		return -ESTALE;
	ret = state.original_connector_fill_modes(connector,
		max_width, max_height);
	state.fill_calls++;
	if (!READ_ONCE(state.installed) || connector != &state.dsi->conn)
		return ret;

	for (slot = 0; slot < PLF110_TOTAL_MODES; slot++)
		move_slot_to_tail(connector, slot);
	validation = validate_connector_locked(connector, true, &scan);
	state.last_error = validation;
	return validation ? validation : ret;
}

static void restore_hooks_locked(void)
{
	if (!state.dsi)
		return;
	if (state.panel_hooked && state.dsi->panel &&
		READ_ONCE(state.dsi->panel->funcs) == &state.hooked_panel_funcs)
		WRITE_ONCE(state.dsi->panel->funcs, state.original_panel_funcs);
	if (state.connector_hooked &&
		READ_ONCE(state.dsi->conn.funcs) == &state.hooked_connector_funcs)
		WRITE_ONCE(state.dsi->conn.funcs,
			state.original_connector_funcs);
	if (state.ext_hooked && state.original_ext_funcs) {
		if (READ_ONCE(state.original_ext_funcs->ext_param_set) ==
			plf110_ext_param_set)
			WRITE_ONCE(state.original_ext_funcs->ext_param_set,
				state.original_ext_set);
		if (READ_ONCE(state.original_ext_funcs->ext_param_get) ==
			plf110_ext_param_get)
			WRITE_ONCE(state.original_ext_funcs->ext_param_get,
				state.original_ext_get);
		if (READ_ONCE(state.original_ext_funcs->mode_switch_update_for_vdo) ==
			plf110_mode_switch_update_for_vdo)
			WRITE_ONCE(
				state.original_ext_funcs->mode_switch_update_for_vdo,
				state.original_vdo_update);
	}
	state.panel_hooked = false;
	state.connector_hooked = false;
	state.ext_hooked = false;
	state.installed = false;
}

static int refresh_modes_internal(void)
{
	struct plf110_scan_result scan;
	struct mtk_dsi *dsi = READ_ONCE(state.dsi);
	int fill_ret;
	int ret;

	if (!dsi || !READ_ONCE(state.installed))
		return -ENODEV;
	state.refreshing = true;
	fill_ret = call_dsi_io(DSI_FILL_MODE_BY_CONNETOR, NULL);
	if (fill_ret < 0) {
		state.refreshing = false;
		return fill_ret;
	}

	mutex_lock(&dsi->conn.dev->mode_config.mutex);
	ret = validate_connector_locked(&dsi->conn, true, &scan);
	mutex_unlock(&dsi->conn.dev->mode_config.mutex);
	if (!ret)
		ret = rebuild_driver_modes();
	state.last_rebuild_error = ret;
	state.refreshing = false;
	if (ret)
		return ret;
	drm_kms_helper_hotplug_event(dsi->conn.dev);
	state.hotplugs++;
	return 0;
}

static int install_hooks(void)
{
	struct plf110_scan_result scan;
	struct mtk_dsi *dsi = READ_ONCE(state.dsi);
	struct mtk_panel_funcs *ext_funcs;
	int ret;

	if (!dsi)
		return -EAGAIN;
	if (state.installed)
		return 0;
	state.stage = 1;
	ret = call_dsi_io(DSI_FILL_MODE_BY_CONNETOR, NULL);
	if (ret < 0)
		return ret;
	if (!dsi->panel || !dsi->panel->funcs || !dsi->conn.funcs ||
		!dsi->ext || !dsi->ext->funcs || !dsi->ddp_comp.mtk_crtc ||
		dsi->ddp_comp.blank_mode)
		return -ENODEV;
	if (dsi->d_rate != 0 || dsi->mipi_hopping_sta ||
		(dsi->data_rate != 0 && dsi->data_rate != PLF110_BASE_DATA_RATE))
		return -EBUSY;

	state.stage = 2;
	state.original_panel_funcs = dsi->panel->funcs;
	state.original_panel_get_modes = dsi->panel->funcs->get_modes;
	state.original_connector_funcs = dsi->conn.funcs;
	state.original_connector_fill_modes = dsi->conn.funcs->fill_modes;
	ext_funcs = dsi->ext->funcs;
	state.original_ext_funcs = ext_funcs;
	state.original_ext_set = ext_funcs->ext_param_set;
	state.original_ext_get = ext_funcs->ext_param_get;
	state.original_vdo_update = ext_funcs->mode_switch_update_for_vdo;
	if (!state.original_panel_get_modes ||
		!state.original_connector_fill_modes ||
		!state.original_ext_set || !state.original_ext_get ||
		state.original_vdo_update)
		return -ESTALE;

	state.stage = 3;
	ret = validate_kcfi(state.original_panel_get_modes,
		plf110_panel_get_modes);
	if (!ret)
		ret = validate_kcfi(state.original_connector_fill_modes,
			plf110_connector_fill_modes);
	if (!ret)
		ret = validate_kcfi(state.original_ext_set,
			plf110_ext_param_set);
	if (!ret)
		ret = validate_kcfi(state.original_ext_get,
			plf110_ext_param_get);
	if (ret)
		return ret;

	mutex_lock(&dsi->conn.dev->mode_config.mutex);
	state.stage = 4;
	ret = validate_connector_locked(&dsi->conn, false, &scan);
	if (!ret)
		ret = prepare_custom_modes_locked();
	if (ret) {
		mutex_unlock(&dsi->conn.dev->mode_config.mutex);
		return ret;
	}
	if (!try_module_get(THIS_MODULE)) {
		mutex_unlock(&dsi->conn.dev->mode_config.mutex);
		return -ENODEV;
	}
	state.self_ref = true;

	memcpy(&state.hooked_panel_funcs, state.original_panel_funcs,
		sizeof(state.hooked_panel_funcs));
	memcpy(&state.hooked_connector_funcs, state.original_connector_funcs,
		sizeof(state.hooked_connector_funcs));
	state.hooked_panel_funcs.get_modes = plf110_panel_get_modes;
	state.hooked_connector_funcs.fill_modes = plf110_connector_fill_modes;
	WRITE_ONCE(ext_funcs->ext_param_set, plf110_ext_param_set);
	WRITE_ONCE(ext_funcs->ext_param_get, plf110_ext_param_get);
	WRITE_ONCE(ext_funcs->mode_switch_update_for_vdo,
		plf110_mode_switch_update_for_vdo);
	WRITE_ONCE(dsi->panel->funcs, &state.hooked_panel_funcs);
	WRITE_ONCE(dsi->conn.funcs, &state.hooked_connector_funcs);
	state.ext_hooked = true;
	state.panel_hooked = true;
	state.connector_hooked = true;
	state.installed = true;
	mutex_unlock(&dsi->conn.dev->mode_config.mutex);

	state.stage = 5;
	ret = refresh_modes_internal();
	if (ret) {
		mutex_lock(&dsi->conn.dev->mode_config.mutex);
		restore_hooks_locked();
		mutex_unlock(&dsi->conn.dev->mode_config.mutex);
		call_dsi_io(DSI_FILL_MODE_BY_CONNETOR, NULL);
		if (state.self_ref) {
			state.self_ref = false;
			module_put(THIS_MODULE);
		}
		return ret;
	}
	state.stage = 6;
	pr_info("plf110_144_mode: installed native-compatible 144Hz mode\n");
	return 0;
}

static int remove_hooks(void)
{
	struct mtk_dsi *dsi = READ_ONCE(state.dsi);
	int ret;

	if (!state.installed)
		return 0;
	if (!dsi)
		return -ENODEV;
	if (dsi->mipi_hopping_sta || dsi->data_rate == PLF110_144_DATA_RATE)
		return -EBUSY;
	mutex_lock(&dsi->conn.dev->mode_config.mutex);
	restore_hooks_locked();
	mutex_unlock(&dsi->conn.dev->mode_config.mutex);
	ret = call_dsi_io(DSI_FILL_MODE_BY_CONNETOR, NULL);
	if (ret >= 0)
		ret = rebuild_driver_modes();
	if (!ret) {
		drm_kms_helper_hotplug_event(dsi->conn.dev);
		state.hotplugs++;
	}
	if (state.self_ref) {
		state.self_ref = false;
		module_put(THIS_MODULE);
	}
	return ret;
}

static int parse_bool_value(const char *value, bool *requested)
{
	if ((value[0] == '1' || value[0] == 'Y' || value[0] == 'y') &&
		(value[1] == '\0' || value[1] == '\n')) {
		*requested = true;
		return 0;
	}
	if ((value[0] == '0' || value[0] == 'N' || value[0] == 'n') &&
		(value[1] == '\0' || value[1] == '\n')) {
		*requested = false;
		return 0;
	}
	return -EINVAL;
}

static int enable_set(const char *value, const struct kernel_param *kp)
{
	bool requested;
	int ret;

	(void)kp;
	ret = parse_bool_value(value, &requested);
	if (ret)
		return ret;
	mutex_lock(&control_lock);
	ret = requested ? install_hooks() : remove_hooks();
	state.last_error = ret;
	mutex_unlock(&control_lock);
	if (ret)
		pr_err("plf110_144_mode: enable=%u failed at stage %u: %d\n",
			requested, state.stage, ret);
	return ret;
}

static int enable_get(char *buffer, const struct kernel_param *kp)
{
	(void)kp;
	return scnprintf(buffer, PAGE_SIZE, "%u\n", state.installed);
}

static int refresh_set(const char *value, const struct kernel_param *kp)
{
	bool requested;
	int ret;

	(void)kp;
	ret = parse_bool_value(value, &requested);
	if (ret || !requested)
		return ret ? ret : -EINVAL;
	mutex_lock(&control_lock);
	ret = refresh_modes_internal();
	state.last_error = ret;
	mutex_unlock(&control_lock);
	return ret;
}

static int status_get(char *buffer, const struct kernel_param *kp)
{
	struct plf110_scan_result scan;
	struct mtk_dsi *dsi = READ_ONCE(state.dsi);
	unsigned int modes = 0;
	int validation = -ENODEV;

	(void)kp;
	if (dsi && dsi->conn.dev) {
		mutex_lock(&dsi->conn.dev->mode_config.mutex);
		validation = scan_connector_locked(&dsi->conn, &scan);
		modes = scan.count;
		mutex_unlock(&dsi->conn.dev->mode_config.mutex);
	}
	return scnprintf(buffer, PAGE_SIZE,
		"installed=%u captured=%u hooks=%u/%u modes=%u "
		"mtk_modes=%u panel_enums=%lu injected=%lu fill_calls=%lu "
		"rebuilds=%lu hotplugs=%lu validation_failures=%lu "
		"ext_gets=%lu ext_sets=%lu mode_switches=%lu "
		"clock_attempts=%lu clock_switches=%lu data_rate=%u "
		"hopping=%u d_rate=%u stage=%u validation=%d "
		"last_rebuild_error=%d last_error=%d\n",
		state.installed, dsi != NULL,
		state.panel_hooked + state.connector_hooked + state.ext_hooked,
		3U, modes, modes, state.panel_enums, state.injected,
		state.fill_calls, state.rebuilds, state.hotplugs,
		state.validation_failures, state.ext_gets, state.ext_sets,
		state.mode_switches, state.clock_attempts,
		state.clock_switches, dsi ? READ_ONCE(dsi->data_rate) : 0,
		dsi ? READ_ONCE(dsi->mipi_hopping_sta) : 0,
		dsi ? READ_ONCE(dsi->d_rate) : 0, state.stage, validation,
		state.last_rebuild_error, state.last_error);
}

static int modes_get(char *buffer, const struct kernel_param *kp)
{
	struct drm_display_mode *mode;
	struct mtk_dsi *dsi = READ_ONCE(state.dsi);
	unsigned int index = 0;
	int length = 0;

	(void)kp;
	if (!dsi || !dsi->conn.dev)
		return scnprintf(buffer, PAGE_SIZE, "captured=0\n");
	mutex_lock(&dsi->conn.dev->mode_config.mutex);
	list_for_each_entry(mode, &dsi->conn.modes, head) {
		length += scnprintf(buffer + length, PAGE_SIZE - length,
			"id=%u %ux%u@%u clock=%d h=%u/%u/%u/%u "
			"v=%u/%u/%u/%u type=0x%x custom=%u\n",
			index++, mode->hdisplay, mode->vdisplay,
			mode_refresh(mode), mode->clock, mode->hdisplay,
			mode->hsync_start, mode->hsync_end, mode->htotal,
			mode->vdisplay, mode->vsync_start, mode->vsync_end,
			mode->vtotal, mode->type,
			custom_slot_for_mode(mode) == 0);
		if (length >= (int)PAGE_SIZE - 128)
			break;
	}
	mutex_unlock(&dsi->conn.dev->mode_config.mutex);
	return length;
}

static const struct kernel_param_ops enable_ops = {
	.set = enable_set,
	.get = enable_get,
};

static const struct kernel_param_ops refresh_ops = {
	.set = refresh_set,
};

static const struct kernel_param_ops status_ops = {
	.get = status_get,
};

static const struct kernel_param_ops modes_ops = {
	.get = modes_get,
};

module_param_cb(enable, &enable_ops, NULL, 0644);
module_param_cb(refresh, &refresh_ops, NULL, 0200);
module_param_cb(status, &status_ops, NULL, 0444);
module_param_cb(modes, &modes_ops, NULL, 0444);

static int __init plf110_144_mode_init(void)
{
	struct device *device;
	int ret;

	state.panel_probe.symbol_name = "drm_panel_get_modes";
	state.panel_probe.pre_handler = panel_pre_handler;
	ret = register_kprobe(&state.panel_probe);
	if (ret)
		return ret;
	state.panel_probe_registered = true;

	state.porch_probe.symbol_name = "mtk_dsi_porch_setting";
	state.porch_probe.pre_handler = porch_pre_handler;
	ret = register_kprobe(&state.porch_probe);
	if (ret) {
		unregister_kprobe(&state.panel_probe);
		state.panel_probe_registered = false;
		return ret;
	}
	state.porch_probe_registered = true;

	device = bus_find_device(&platform_bus_type, NULL,
		PLF110_PRIMARY_DSI, match_primary_dsi);
	if (device) {
		capture_dsi(dev_get_drvdata(device), "platform scan");
		put_device(device);
	}
	pr_info("plf110_144_mode: loaded disabled; waiting for enable=1\n");
	return 0;
}

static void __exit plf110_144_mode_exit(void)
{
	if (state.porch_probe_registered)
		unregister_kprobe(&state.porch_probe);
	if (state.panel_probe_registered)
		unregister_kprobe(&state.panel_probe);
	pr_info("plf110_144_mode: unloaded captures=%lu fills=%lu rebuilds=%lu\n",
		state.captures, state.fill_calls, state.rebuilds);
}

module_init(plf110_144_mode_init);
module_exit(plf110_144_mode_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("酷安丛雨颜烬 × OpenAI Codex");
MODULE_DESCRIPTION("Runtime PLF110 AA600 native-compatible 144Hz display mode");
MODULE_INFO(name, KBUILD_MODNAME);
MODULE_INFO(depends, "");
MODULE_INFO(vermagic, PLF110_VERMAGIC);

/*
 * The public reference is linked without the kernel modpost step.  These
 * records are pinned to the exact validated PLF110 kernel build named above.
 */
__visible struct module __this_module
__section(".gnu.linkonce.this_module") = {
	.name = KBUILD_MODNAME,
	.init = init_module,
#ifdef CONFIG_MODULE_UNLOAD
	.exit = cleanup_module,
#endif
	.arch = MODULE_ARCH_INIT,
};

static const struct modversion_info ____versions[]
__used __section("__versions") = {
	{ 0xea759d7f, "module_layout" },
	{ 0x68f31cbd, "__list_add_valid" },
	{ 0xe1537255, "__list_del_entry_valid" },
	{ 0x92997ed8, "_printk" },
	{ 0x1348649e, "alt_cb_patch_nops" },
	{ 0x78729785, "bus_find_device" },
	{ 0x263c3152, "bcmp" },
	{ 0x4531ab62, "copy_from_kernel_nofault" },
	{ 0x407f8acf, "drm_kms_helper_hotplug_event" },
	{ 0xff193a01, "drm_mode_duplicate" },
	{ 0x88f2da8e, "drm_mode_probed_add" },
	{ 0x4a35d30d, "drm_mode_set_name" },
	{ 0x4829a47e, "memcpy" },
	{ 0x28f42c1d, "module_put" },
	{ 0xd5977bfb, "mutex_lock" },
	{ 0xed55cabd, "mutex_unlock" },
	{ 0xdede9e3e, "platform_bus_type" },
	{ 0xc0052169, "put_device" },
	{ 0x0472cf3b, "register_kprobe" },
	{ 0x96848186, "scnprintf" },
	{ 0xe2d5255a, "strcmp" },
	{ 0xda2e6300, "try_module_get" },
	{ 0xeb78b1ed, "unregister_kprobe" },
};
