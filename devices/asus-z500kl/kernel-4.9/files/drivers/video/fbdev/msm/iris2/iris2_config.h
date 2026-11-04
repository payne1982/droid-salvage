/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef IRIS2_CONFIG_H
#define IRIS2_CONFIG_H
#include <linux/msm_iris2.h>
#include <linux/workqueue.h>
#include <linux/mutex.h>
#include <linux/spinlock.h>
#if defined(CONFIG_IRIS2_LIGHTUP_ONLY) || defined(CONFIG_IRIS2_FULL_SUPPORT) || defined(CONFIG_IRIS2P_FULL_SUPPORT) || defined(CONFIG_IRIS2P_LIGHTUP_ONLY)
struct iris_dtg_info {
	u32 dtg_ctrl;
	u32 dtg_ctrl_1;
	u32 evs_dly;
	u32 evs_new_dly;
	u32 dtg_delay;
	u32 te_ctrl;
	u32 te_ctrl_1;
	u32 te_ctrl_2;
	u32 te_ctrl_3;
	u32 te_ctrl_4;
	u32 te_ctrl_5;
	u32 te_dly;
	u32 te_dly_1;
	u32 dvs_ctrl;
	u32 vfp_ctrl_0;
	u32 vfp_ctrl_1;
};

struct iris_config {
	bool fbo_debug_enabled;
	bool sbs_debug_enabled;
	void __iomem *yuv_frame_addr_reg;
	bool driver_initialized;
	bool memc_enable;
	bool mode_switch_finish; ///TODO: remove it
	bool video_on;
	bool fbo_enable;
	u8 repeat;
	bool nrv_enable;
	bool true_cut_enable;
	int sf_notify_mode;
	int current_mode;
	uint32_t frc_path;
	uint32_t pt_path;
	uint32_t rfb_path;
	atomic_t mode_switch_cnt;
	bool ready;
	bool cap_enable;
	bool cap_change;
	bool iris_ratio_updated;
	uint32_t lp_frc_timing;
	spinlock_t iris_reset_lock;
	bool memc_perf_hack;
	bool check_pwil_rfb_ready;
	bool check_appcode_rfb_ready;
#if defined(CONFIG_IRIS2_DRC_SUPPORT) || defined(CONFIG_IRIS2P_DRC_SUPPORT)
	bool drc_enable;
	uint32_t drc_size; // V<<16|H, it will be set as pwil.cap.size
#endif
#if defined(CONFIG_IRIS2P_FULL_SUPPORT)
	bool sf_mode_change_start;
	int kickoff_cnt;
	struct dentry *dbg_root;
#elif defined(CONFIG_IRIS2_LIGHTUP_ONLY) || defined(CONFIG_IRIS2_FULL_SUPPORT)
	bool mode_changed;
	int rfb_delay;
	int frc_delay;
	int prep_delay;
#endif
	unsigned int input_frame_rate;
	unsigned int output_frame_rate;
	unsigned int input_vfr;
	unsigned int in_ratio;
	unsigned int out_ratio;
	unsigned int scale;
	unsigned int vp_continous;
#if defined(CONFIG_IRIS2_FULL_SUPPORT) || defined(CONFIG_IRIS2P_FULL_SUPPORT)
	struct iris_meta meta;
	struct iris_meta meta_set;
#if defined(CONFIG_IRIS2P_FULL_SUPPORT)
	struct iris_available_mode avail_mode;
#endif
#endif
	unsigned int prev_vts;
	unsigned int prev_dvts;
	unsigned int sw_te_period;
	unsigned int val_frcc_cmd_th;
	unsigned int val_frcc_reg8;
	unsigned int val_frcc_reg16;
	unsigned int val_frcc_reg17;
#if defined(CONFIG_IRIS2P_FULL_SUPPORT) || defined(CONFIG_IRIS2P_LIGHTUP_ONLY)
	bool pt_switch;
	struct iris_dtg_info dtg_setting;
	unsigned int tx_switch_state;
	unsigned int tx_switch_new_mode;
	unsigned int tx_switch_debug_flag;
#endif

	struct workqueue_struct *iris_wq;
	struct work_struct pt_work;
	struct work_struct pt_prepare_work;
	struct work_struct rfb_work;
	struct work_struct rfb_prepare_work;
	struct work_struct memc_prepare_work;
	struct work_struct memc_cancel_work;
	struct work_struct memc_work;
	struct mutex cmd_mutex;
	struct mutex config_mutex;
	struct mutex meta_mutex;
};
#endif // CONFIG_IRIS2_LIGHTUP_ONLY || CONFIG_IRIS2_FULL_SUPPORT || CONFIG_IRIS2P_FULL_SUPPORT || CONFIG_IRIS2P_LIGHTUP_ONLY

#endif
