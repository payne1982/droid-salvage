/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef IRIS2_MDSS_H
#define IRIS2_MDSS_H
#include <linux/types.h>
struct msm_fb_data_type;
struct mdss_mdp_ctl;
struct mdss_mdp_pipe;
struct mdss_dsi_ctrl_pdata;
struct mdss_panel_info;
struct mdss_panel_data;
struct device_node;
int iris2_mdss_attach(struct msm_fb_data_type *mfd);
void iris2_mdss_detach(struct msm_fb_data_type *mfd);
void iris2_mdss_quiesce(struct msm_fb_data_type *mfd);
void iris2_mdss_resume(struct msm_fb_data_type *mfd);
void iris2_mdss_forget_ctl(struct mdss_mdp_ctl *ctl);
int iris2_mdss_ioctl(struct msm_fb_data_type *mfd, unsigned int cmd, void __user *argp);
void iris2_mdss_cmd_frame(struct mdss_mdp_ctl *ctl);
void iris2_mdss_video_frame(struct mdss_mdp_ctl *ctl);
void iris2_mdss_cadence(struct mdss_mdp_ctl *ctl);
void iris2_mdss_track_pipe(struct msm_fb_data_type *mfd, struct mdss_mdp_pipe *pipe);
void iris2_mdss_forget_pipe(struct mdss_mdp_pipe *pipe);
u32 iris2_mdss_read_video_count(struct mdss_mdp_ctl *ctl);
int iris2_mdss_panel_on(struct mdss_dsi_ctrl_pdata *ctrl);
void iris2_mdss_panel_off(struct mdss_dsi_ctrl_pdata *ctrl);
int iris2_mdss_splash(struct mdss_panel_data *pdata);
void iris2_mdss_parse(struct device_node *np, struct mdss_panel_info *info);
void iris2_mdss_panel_release(struct mdss_panel_data *pdata);
/* Bridge-specific register operation kept in the MDSS binding. */
void iris2_mdss_hs_mode(int enable, struct mdss_panel_data *pdata);
#endif
