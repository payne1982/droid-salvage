/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef IRIS2_LIFECYCLE_H
#define IRIS2_LIFECYCLE_H
#include "iris2_config.h"
struct msm_fb_data_type;
struct work_struct;
struct iris_config *iris2_get_config(struct msm_fb_data_type *mfd);
int iris2_lifecycle_attach(struct msm_fb_data_type *mfd);
void iris2_lifecycle_quiesce(struct msm_fb_data_type *mfd);
void iris2_lifecycle_resume(struct msm_fb_data_type *mfd);
void iris2_lifecycle_panel_ready(struct msm_fb_data_type *mfd);
void iris2_lifecycle_detach(struct msm_fb_data_type *mfd);
bool iris2_operation_begin(struct msm_fb_data_type *mfd);
bool iris2_operation_begin_epoch(unsigned int epoch);
void iris2_operation_end(void);
bool iris2_irq_begin(struct msm_fb_data_type *mfd);
void iris2_irq_end(void);
unsigned int iris2_lifecycle_epoch(void);
bool iris2_queue_work(struct work_struct *work, bool counted);
void iris2_run_work(struct work_struct *work,
		void (*run)(struct work_struct *), bool counted);
void iris2_core_cancel_work(struct msm_fb_data_type *mfd);
void iris2_core_release(struct msm_fb_data_type *mfd);
#endif
