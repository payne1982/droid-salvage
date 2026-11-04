// SPDX-License-Identifier: GPL-2.0-only
/* Z500KL ADSP boot control. Retain /sys/kernel/boot_adsp/boot for Android init.
 * Boot is synchronous, as on the working ASUS kernel: no firmware worker may
 * outlive its device or race an unload. Subsystem/PIL code remains unchanged.
 */
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/slab.h>
#include <linux/sysfs.h>
#include <linux/mutex.h>
#include <soc/qcom/subsystem_restart.h>
#include <ipc/apr.h>

struct z500kl_adsp_loader {
	struct device *dev;
	struct kobject *kobj;
	struct mutex lock;
	const char *subsystem;
	void *handle;
};
static DEFINE_MUTEX(loader_owner_lock);
static struct z500kl_adsp_loader *loader_owner;

static ssize_t boot_store(struct kobject *kobj, struct kobj_attribute *attr,
			  const char *buf, size_t count)
{
	struct z500kl_adsp_loader *loader;
	unsigned int command;
	void *handle;
	int ret;

	ret = kstrtouint(buf, 0, &command);
	if (ret || command > 1)
		return ret ? ret : -EINVAL;
	mutex_lock(&loader_owner_lock);
	loader = loader_owner;
	if (!loader || loader->kobj != kobj) {
		mutex_unlock(&loader_owner_lock);
		return -ENODEV;
	}
	mutex_lock(&loader->lock);
	mutex_unlock(&loader_owner_lock);
	ret = 0;
	if (command && !loader->handle) {
		handle = subsystem_get(loader->subsystem);
		if (IS_ERR(handle)) {
			ret = PTR_ERR(handle);
			dev_err(loader->dev, "unable to boot %s: %d\n",
				loader->subsystem, ret);
		} else {
			loader->handle = handle;
			if (!strcmp(loader->subsystem, "adsp"))
				apr_set_q6_state(APR_SUBSYS_LOADED);
			else
				apr_set_modem_state(APR_SUBSYS_LOADED);
		}
	} else if (!command && loader->handle) {
		subsystem_put(loader->handle);
		loader->handle = NULL;
	}
	mutex_unlock(&loader->lock);
	return ret ? ret : count;
}
static struct kobj_attribute boot_attribute = __ATTR(boot, 0220, NULL, boot_store);

static int adsp_loader_probe(struct platform_device *pdev)
{
	struct z500kl_adsp_loader *loader;
	int ret;

	loader = devm_kzalloc(&pdev->dev, sizeof(*loader), GFP_KERNEL);
	if (!loader)
		return -ENOMEM;
	loader->dev = &pdev->dev;
	loader->subsystem = "adsp";
	of_property_read_string(pdev->dev.of_node, "qcom,proc-img-to-load",
				&loader->subsystem);
	if (strcmp(loader->subsystem, "adsp") && strcmp(loader->subsystem, "modem"))
		return -EINVAL;
	mutex_init(&loader->lock);
	mutex_lock(&loader_owner_lock);
	if (loader_owner) {
		mutex_unlock(&loader_owner_lock);
		return -EBUSY;
	}
	loader->kobj = kobject_create_and_add("boot_adsp", kernel_kobj);
	if (!loader->kobj) {
		mutex_unlock(&loader_owner_lock);
		return -ENOMEM;
	}
	loader_owner = loader;
	mutex_unlock(&loader_owner_lock);
	ret = sysfs_create_file(loader->kobj, &boot_attribute.attr);
	if (ret) {
		mutex_lock(&loader_owner_lock);
		loader_owner = NULL;
		mutex_unlock(&loader_owner_lock);
		kobject_put(loader->kobj);
		return ret;
	}
	platform_set_drvdata(pdev, loader);
	return 0;
}

static int adsp_loader_remove(struct platform_device *pdev)
{
	struct z500kl_adsp_loader *loader = platform_get_drvdata(pdev);

	mutex_lock(&loader_owner_lock);
	if (loader_owner == loader)
		loader_owner = NULL;
	mutex_unlock(&loader_owner_lock);
	/* kernfs drains active sysfs callbacks before private data is released. */
	sysfs_remove_file(loader->kobj, &boot_attribute.attr);
	mutex_lock(&loader->lock);
	if (loader->handle) {
		subsystem_put(loader->handle);
		loader->handle = NULL;
	}
	mutex_unlock(&loader->lock);
	kobject_put(loader->kobj);
	return 0;
}
static const struct of_device_id adsp_loader_match[] = {
	{ .compatible = "qcom,adsp-loader" }, { }
};
MODULE_DEVICE_TABLE(of, adsp_loader_match);
static struct platform_driver adsp_loader_driver = {
	.probe = adsp_loader_probe,
	.remove = adsp_loader_remove,
	.driver = { .name = "adsp-loader", .of_match_table = adsp_loader_match },
};
module_platform_driver(adsp_loader_driver);
MODULE_DESCRIPTION("Z500KL ADSP boot control over the native subsystem API");
MODULE_LICENSE("GPL v2");
