/* SPDX-License-Identifier: GPL-2.0-only */
#include <linux/slab.h>
#include <linux/wait.h>
#include "mdss_dsi_iris2.h"
#include "mdss_dsi_iris2_extern.h"
#include "mdss_dsi_iris2_dbg.h"
#include "iris2_io.h"
#include "iris2_lifecycle.h"
#include "iris2_lifecycle_state.h"

/* One physical Iris2 bridge on Z500KL. Nothing is embedded in MDSS objects. */
static struct {
	struct iris2_life_state state;
	struct msm_fb_data_type *mfd;
	struct iris_config config;
	struct workqueue_struct *wq;
	bool admission_enabled;
} iris2_device;
static DEFINE_SPINLOCK(iris2_state_lock);
static DEFINE_MUTEX(iris2_transition_lock);
static DEFINE_MUTEX(iris2_operation_lock);
static DECLARE_WAIT_QUEUE_HEAD(iris2_users_wait);

struct iris_config *iris2_get_config(struct msm_fb_data_type *mfd)
{
	return mfd && mfd == READ_ONCE(iris2_device.mfd) ? &iris2_device.config : NULL;
}

static bool iris2_get(struct msm_fb_data_type *mfd, unsigned int epoch)
{
	unsigned long flags;
	bool ok;

	spin_lock_irqsave(&iris2_state_lock, flags);
	ok = iris2_device.mfd && (!mfd || mfd == iris2_device.mfd) &&
		iris2_state_get(&iris2_device.state, epoch);
	spin_unlock_irqrestore(&iris2_state_lock, flags);
	return ok;
}

static void iris2_put(void)
{
	unsigned long flags;
	bool idle;

	spin_lock_irqsave(&iris2_state_lock, flags);
	WARN_ON(!iris2_state_put(&iris2_device.state));
	idle = !iris2_device.state.users;
	spin_unlock_irqrestore(&iris2_state_lock, flags);
	if (idle)
		wake_up_all(&iris2_users_wait);
}

static bool iris2_enter(struct msm_fb_data_type *mfd, unsigned int epoch)
{
	unsigned long flags;
	bool running;

	if (!iris2_get(mfd, epoch))
		return false;
	mutex_lock(&iris2_operation_lock);
	spin_lock_irqsave(&iris2_state_lock, flags);
	running = iris2_device.state.phase == IRIS2_ACTIVE;
	spin_unlock_irqrestore(&iris2_state_lock, flags);
	if (!running) {
		mutex_unlock(&iris2_operation_lock);
		iris2_put();
	}
	return running;
}

bool iris2_operation_begin(struct msm_fb_data_type *mfd)
{
	return mfd && iris2_enter(mfd, 0);
}
bool iris2_operation_begin_epoch(unsigned int epoch)
{
	return epoch && iris2_enter(NULL, epoch);
}
void iris2_operation_end(void)
{
	mutex_unlock(&iris2_operation_lock);
	iris2_put();
}
bool iris2_irq_begin(struct msm_fb_data_type *mfd)
{
	return mfd && iris2_get(mfd, 0);
}
void iris2_irq_end(void)
{
	iris2_put();
}

unsigned int iris2_lifecycle_epoch(void)
{
	unsigned long flags;
	unsigned int epoch;

	spin_lock_irqsave(&iris2_state_lock, flags);
	epoch = iris2_device.mfd ? iris2_device.state.epoch : 0;
	spin_unlock_irqrestore(&iris2_state_lock, flags);
	return epoch;
}

bool iris2_queue_work(struct work_struct *work, bool counted)
{
	unsigned long flags;
	bool queued = false;

	spin_lock_irqsave(&iris2_state_lock, flags);
	if (iris2_device.state.phase == IRIS2_ACTIVE && iris2_device.wq) {
		queued = queue_work(iris2_device.wq, work);
		if (queued && counted)
			atomic_inc(&iris2_device.config.mode_switch_cnt);
	}
	spin_unlock_irqrestore(&iris2_state_lock, flags);
	return queued;
}

void iris2_run_work(struct work_struct *work,
		void (*run)(struct work_struct *), bool counted)
{
	if (iris2_enter(NULL, 0)) {
		run(work);
		iris2_operation_end();
	}
	if (counted)
		atomic_dec_if_positive(&iris2_device.config.mode_switch_cnt);
}

/* Caller holds transition_lock. Called before MDSS acquires its shutdown locks. */
static void iris2_stop(struct msm_fb_data_type *mfd, bool detach)
{
	unsigned long flags;
	struct iris_config *cfg = &iris2_device.config;
	bool interrupted;

	spin_lock_irqsave(&iris2_state_lock, flags);
	iris2_device.admission_enabled = false;
	iris2_state_stop(&iris2_device.state);
	spin_unlock_irqrestore(&iris2_state_lock, flags);
	interrupted = atomic_read(&cfg->mode_switch_cnt) != 0;
	iris2_core_cancel_work(mfd);
	wait_event(iris2_users_wait, !READ_ONCE(iris2_device.state.users));
	/* Revisit interrupted mode requests and bandwidth votes on the next frame. */
	if (interrupted || cfg->memc_perf_hack)
		cfg->mode_changed = true;
	iris_debugfs_quiesce(mfd);
	atomic_set(&cfg->mode_switch_cnt, 0);
	WRITE_ONCE(cfg->yuv_frame_addr_reg, NULL);
	g_dsi_ctrl = NULL;
	if (cfg->memc_perf_hack) {
		iris2_io_bimc_enable(0);
		iris2_io_snoc_enable(0);
		cfg->memc_perf_hack = false;
	}
	spin_lock_irqsave(&iris2_state_lock, flags);
	if (!detach)
		WARN_ON(!iris2_state_idle(&iris2_device.state));
	spin_unlock_irqrestore(&iris2_state_lock, flags);
}

void iris2_lifecycle_quiesce(struct msm_fb_data_type *mfd)
{
	mutex_lock(&iris2_transition_lock);
	if (mfd && mfd == iris2_device.mfd)
		iris2_stop(mfd, false);
	mutex_unlock(&iris2_transition_lock);
}

void iris2_lifecycle_resume(struct msm_fb_data_type *mfd)
{
	unsigned long flags;

	spin_lock_irqsave(&iris2_state_lock, flags);
	if (mfd && mfd == iris2_device.mfd &&
	    iris2_device.state.phase != IRIS2_QUIESCING &&
	    iris2_device.state.phase != IRIS2_DEAD) {
		iris2_device.admission_enabled = true;
		if (iris2_device.config.ready)
			iris2_state_activate(&iris2_device.state);
	}
	spin_unlock_irqrestore(&iris2_state_lock, flags);
}

/* Panel callbacks can run during an off-path cleanup kickoff. Only explicit
 * MDSS on/post-switch completion may allow new operations after quiesce. */
void iris2_lifecycle_panel_ready(struct msm_fb_data_type *mfd)
{
	unsigned long flags;

	spin_lock_irqsave(&iris2_state_lock, flags);
	if (mfd && mfd == iris2_device.mfd && iris2_device.admission_enabled &&
	    iris2_device.config.ready)
		iris2_state_activate(&iris2_device.state);
	spin_unlock_irqrestore(&iris2_state_lock, flags);
}

int iris2_lifecycle_attach(struct msm_fb_data_type *mfd)
{
	unsigned long flags;
	int ret = 0;

	if (!mfd || mfd->index != 0 || (mfd->panel.type != MIPI_CMD_PANEL &&
	    mfd->panel.type != MIPI_VIDEO_PANEL))
		return 0;
	mutex_lock(&iris2_transition_lock);
	if (iris2_device.mfd) {
		ret = iris2_device.mfd == mfd ? 0 : -EBUSY;
		goto out;
	}
	iris2_device.wq = alloc_ordered_workqueue("iris2", WQ_MEM_RECLAIM);
	if (!iris2_device.wq) {
		ret = -ENOMEM;
		goto out;
	}
	memset(&iris2_device.config, 0, sizeof(iris2_device.config));
	iris2_device.admission_enabled = false;
	spin_lock_irqsave(&iris2_state_lock, flags);
	WARN_ON(!iris2_state_bind(&iris2_device.state));
	iris2_device.mfd = mfd;
	spin_unlock_irqrestore(&iris2_state_lock, flags);
	ret = mdss_dsi_iris_init(mfd);
	if (!ret && iris_debugfs_init(mfd)) {
		/* Debugfs is optional, including on kernels built without DEBUG_FS. */
		iris_debugfs_cleanup();
		pr_warn("iris2: debugfs unavailable; continuing without debug files\n");
	}
	if (ret) {
		iris_debugfs_cleanup();
		iris2_core_release(mfd);
		destroy_workqueue(iris2_device.wq);
		iris2_device.wq = NULL;
		spin_lock_irqsave(&iris2_state_lock, flags);
		iris2_device.mfd = NULL;
		WARN_ON(!iris2_state_unbind(&iris2_device.state));
		spin_unlock_irqrestore(&iris2_state_lock, flags);
	}
out:
	mutex_unlock(&iris2_transition_lock);
	return ret;
}

void iris2_lifecycle_detach(struct msm_fb_data_type *mfd)
{
	unsigned long flags;

	mutex_lock(&iris2_transition_lock);
	if (!mfd || mfd != iris2_device.mfd)
		goto out;
	iris2_stop(mfd, true);
	iris_debugfs_cleanup();
	iris2_core_release(mfd);
	destroy_workqueue(iris2_device.wq);
	iris2_device.wq = NULL;
	spin_lock_irqsave(&iris2_state_lock, flags);
	iris2_device.mfd = NULL;
	WARN_ON(!iris2_state_unbind(&iris2_device.state));
	spin_unlock_irqrestore(&iris2_state_lock, flags);
out:
	mutex_unlock(&iris2_transition_lock);
}
