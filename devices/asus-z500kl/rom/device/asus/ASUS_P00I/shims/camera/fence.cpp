/*
 * android::Fence::~Fence(), out of line.
 *
 * In Nougat the destructor was defined in libui and the camera HAL, which holds
 * sp<Fence>s for its preview buffers, calls it when the last reference goes. Pie
 * made it "= default" in the header, private, so libui no longer exports it and the
 * HAL fails to load with an unresolved _ZN7android5FenceD1Ev.
 *
 * Pie's default destructor does one thing: base::unique_fd's, which closes the
 * fence fd; LightRefBase's is trivial. Nougat's did the same. So this does that,
 * under the name the HAL looks for. It cannot simply call fence->~Fence(): that
 * would make the compiler emit the inline destructor under this very name. The
 * member is private, hence the define.
 */

#define private public
#include <ui/Fence.h>
#undef private

extern "C" void _ZN7android5FenceD1Ev(android::Fence* fence) {
    fence->mFenceFd.reset();
}
