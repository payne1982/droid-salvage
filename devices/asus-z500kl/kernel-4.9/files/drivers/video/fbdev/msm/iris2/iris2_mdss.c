/* SPDX-License-Identifier: GPL-2.0-only */
/* MDSS 4.9 binding. Keep core Iris state out of generic MDSS structures. */
#include "mdss_dsi_iris2.h"
#include "mdss_dsi_iris2_lightup.h"
#include "mdss_dsi_iris2_mode_switch.h"
#include "mdss_dsi_iris2_ioctl.h"
#include "mdss_dsi_iris2_extern.h"
#include "mdss_dsi_iris2_dbg.h"
#include "iris2_lifecycle.h"

static bool iris2_splash_done;
/* Serialize cadence state and register invalidation without sleeping in IRQ. */
static DEFINE_SPINLOCK(iris2_cadence_lock);

u32 iris2_mdss_read_video_count(struct mdss_mdp_ctl *ctl)
{
	struct mdss_data_type *mdata;
	void __iomem *base;
	u32 count, intf;

	if (!ctl || !ctl->intf_ctx[MASTER_CTX] || !ctl->is_video_mode)
		return 0;
	mdata = ctl->mdata;
	intf = ctl->intf_num - MDSS_MDP_INTF0;
	if (!mdata || !mdata->video_intf || intf >= mdata->nintf)
		return 0;
	base = mdss_mdp_get_intf_base_addr(mdata, intf);
	if (!base)
		return 0;
	mdss_mdp_clk_ctrl(MDP_BLOCK_POWER_ON);
	count = readl_relaxed(base + MDSS_MDP_REG_INTF_FRAME_COUNT);
	mdss_mdp_clk_ctrl(MDP_BLOCK_POWER_OFF);
	return count;
}

void iris2_mdss_hs_mode(int enable, struct mdss_panel_data *pdata)
{
	struct mdss_dsi_ctrl_pdata *ctrl;
	u32 value;

	if (!pdata)
		return;
	ctrl = container_of(pdata, struct mdss_dsi_ctrl_pdata, panel_data);
	value = MIPI_INP(ctrl->ctrl_base + 0x003c);
	if (enable)
		value &= ~BIT(26);
	else
		value |= BIT(26);
	MIPI_OUTP(ctrl->ctrl_base + 0x003c, value);
}
int iris2_mdss_attach(struct msm_fb_data_type *mfd)
{
	int ret = iris2_lifecycle_attach(mfd);

	if (!ret && mfd->index == 0)
		iris2_splash_done = false;
	return ret;
}
void iris2_mdss_detach(struct msm_fb_data_type *mfd)
{
	iris2_lifecycle_detach(mfd);
}
void iris2_mdss_quiesce(struct msm_fb_data_type *mfd)
{
	iris2_lifecycle_quiesce(mfd);
}
void iris2_mdss_resume(struct msm_fb_data_type *mfd)
{
	iris2_lifecycle_resume(mfd);
}
void iris2_mdss_forget_ctl(struct mdss_mdp_ctl *ctl)
{
	iris_debugfs_forget_ctl(ctl);
}
int iris2_mdss_ioctl(struct msm_fb_data_type *mfd, unsigned int cmd, void __user *argp)
{
	int ret;

	/* Preserve the existing fallback for non-Iris commands. */
	if (_IOC_TYPE(cmd) != MSMFB_IOCTL_MAGIC || _IOC_NR(cmd) < 200 || _IOC_NR(cmd) > 214)
		return -ENOTSUPP;
	if (!iris2_operation_begin(mfd))
		return -EHOSTDOWN;
	ret = iris2_ioctl(mfd, cmd, argp);
	iris2_operation_end();
	return ret;
}
void iris2_mdss_cmd_frame(struct mdss_mdp_ctl *ctl)
{
	if (!ctl->is_master || !iris2_operation_begin(ctl->mfd))
		return;
	iris_copy_meta(ctl->mfd);
	iris_mode_switch_cmd(ctl->mfd);
	iris_frc_repeat(ctl->mfd);
	iris_calc_nrv(ctl);
	iris_calc_meta(ctl->mfd);
	iris_set_configure(ctl->mfd);
	iris_send_meta_cmd(ctl);
	iris2_operation_end();
}
void iris2_mdss_video_frame(struct mdss_mdp_ctl *ctl)
{
	if (ctl->mfd->panel_info->type != MIPI_VIDEO_PANEL ||
	    !iris2_operation_begin(ctl->mfd))
		return;
	iris_mode_switch_video(ctl->mfd);
	iris_copy_meta(ctl->mfd);
	iris_frc_repeat(ctl->mfd);
	iris_calc_nrv(ctl);
	iris_set_configure(ctl->mfd);
	if (iris_calc_meta(ctl->mfd))
		iris_send_meta_video(ctl);
	iris2_operation_end();
}
void iris2_mdss_cadence(struct mdss_mdp_ctl *ctl)
{
	unsigned long flags;

	if (!ctl->is_master || !iris2_irq_begin(ctl->mfd))
		return;
	spin_lock_irqsave(&iris2_cadence_lock, flags);
	iris_cmd_cadence_check(ctl);
	spin_unlock_irqrestore(&iris2_cadence_lock, flags);
	iris2_irq_end();
}
void iris2_mdss_track_pipe(struct msm_fb_data_type *mfd, struct mdss_mdp_pipe *pipe)
{
	struct iris_config *cfg;
	unsigned long flags;

	if (pipe->type != MDSS_MDP_PIPE_TYPE_VIG || !iris2_irq_begin(mfd))
		return;
	cfg = iris2_get_config(mfd);
	spin_lock_irqsave(&iris2_cadence_lock, flags);
	WRITE_ONCE(cfg->yuv_frame_addr_reg, pipe->base + MDSS_MDP_REG_SSPP_SRC0_ADDR);
	spin_unlock_irqrestore(&iris2_cadence_lock, flags);
	iris2_irq_end();
}

void iris2_mdss_forget_pipe(struct mdss_mdp_pipe *pipe)
{
	struct msm_fb_data_type *mfd = READ_ONCE(g_mfd);
	struct iris_config *cfg;
	unsigned long flags;

	if (!iris2_irq_begin(mfd))
		return;
	cfg = iris2_get_config(mfd);
	spin_lock_irqsave(&iris2_cadence_lock, flags);
	if (cfg->yuv_frame_addr_reg == pipe->base + MDSS_MDP_REG_SSPP_SRC0_ADDR)
		WRITE_ONCE(cfg->yuv_frame_addr_reg, NULL);
	spin_unlock_irqrestore(&iris2_cadence_lock, flags);
	iris2_irq_end();
}
int iris2_mdss_panel_on(struct mdss_dsi_ctrl_pdata *ctrl)
{
	if (!g_mfd || !iris2_get_config(g_mfd))
		return -ENODEV;
	iris2_init(ctrl);
	iris2_panel_cmds(ctrl, PANEL_ON_CMDS);
	iris2_lightup(ctrl);
	return 0;
}
void iris2_mdss_panel_off(struct mdss_dsi_ctrl_pdata *ctrl)
{
	if (!g_mfd || !iris2_get_config(g_mfd))
		return;
	iris2_lightoff(ctrl);
	iris2_panel_cmds(ctrl, PANEL_OFF_CMDS);
	iris2_lightoff_finish(ctrl);
}
int iris2_mdss_splash(struct mdss_panel_data *pdata)
{
	if (iris2_splash_done)
		return 0;
	iris2_splash_done = true;
	pr_info("iris2: splash firmware download on first unblank\n");
	return iris_fw_download_cont_splash(pdata, false);
}
void iris2_mdss_parse(struct device_node *np, struct mdss_panel_info *info)
{
	mdss_dsi_parse_iris_params(np, info);
	mdss_dsi_parse_iris_mipi(np, info->mipi.mode, info->pdest);
}
void iris2_mdss_panel_release(struct mdss_panel_data *pdata)
{
	struct msm_fb_data_type *mfd = READ_ONCE(g_mfd);
	struct mdss_panel_data *panel;

	/* Drain Iris users before this controller loses clocks or MMIO. */
	if (mfd) {
		panel = dev_get_platdata(&mfd->pdev->dev);
		for (; panel; panel = panel->next) {
			if (panel == pdata) {
				iris2_lifecycle_detach(mfd);
				break;
			}
		}
	}
	iris2_panel_release(pdata);
}
