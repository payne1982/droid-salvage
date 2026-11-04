#ifndef MDSS_DSI_IRIS2_DBG_H
#define MDSS_DSI_IRIS2_DBG_H

int iris_debugfs_init(struct msm_fb_data_type *mfd);


void iris_debugfs_quiesce(struct msm_fb_data_type *mfd);
void iris_debugfs_cleanup(void);
void iris_debugfs_forget_ctl(struct mdss_mdp_ctl *ctl);

#endif
