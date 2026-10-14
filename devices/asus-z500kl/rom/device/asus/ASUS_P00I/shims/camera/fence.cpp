/*
 * android::Fence as ASUS' Nougat camera HAL (camera.msm8952.so) was built against it.
 *
 * In Nougat a Fence was 8 bytes: LightRefBase's reference count, then the fd. The HAL
 * allocates that much with operator new, and whatever it inlined uses those offsets.
 * Android 13's Fence has virtual functions, so a vtable pointer comes first, the count
 * and the fd move to 4 and 8, and the object is 12 bytes. Android 13's constructor,
 * run on the HAL's 8 bytes, writes the fd past the end of them, onto
 * whatever the allocator put next: a few frames after a photo is taken or the camera is
 * closed, gralloc finds a pointer of its own overwritten and the HAL process dies.
 * Pie's Fence still had Nougat's layout; the HAL only needed the destructor, which Pie
 * no longer exported.
 *
 * So the HAL gets, under the names it imports, every out-of-line function it uses on a
 * Fence, laid out as it expects: the constructor, wait(), the destructor, and
 * sp<Fence>'s constructor and destructor, which hold the reference count.
 * TARGET_LD_SHIM_LIBS loads this library ahead of the HAL's own dependencies, so these
 * are the definitions the HAL binds to; the rest of the process keeps Android 13's.
 * The HAL imports nothing else that takes a Fence.
 *
 * On 32-bit ARM, constructors and destructors return `this`.
 */

#include <errno.h>
#include <stdint.h>
#include <unistd.h>

#include <atomic>
#include <new>

#include <android/sync.h>

namespace {

struct NougatFence {
    std::atomic<int32_t> count;  // LightRefBase<Fence>::mCount
    int fd;                      // Fence::mFenceFd
};
static_assert(sizeof(NougatFence) == 8, "the HAL allocates 8 bytes for a Fence");

struct SpFence {
    NougatFence* ptr;  // sp<Fence>::m_ptr
};

}  // namespace

extern "C" {

// android::Fence::Fence(int)
NougatFence* _ZN7android5FenceC1Ei(NougatFence* fence, int fd) {
    new (&fence->count) std::atomic<int32_t>(0);
    fence->fd = fd;
    return fence;
}

// android::Fence::wait(int), as Nougat's: no fence is a fence already signalled.
int _ZN7android5Fence4waitEi(NougatFence* fence, int timeout) {
    if (fence->fd == -1) return 0;
    return sync_wait(fence->fd, timeout) < 0 ? -errno : 0;
}

// android::Fence::~Fence()
NougatFence* _ZN7android5FenceD1Ev(NougatFence* fence) {
    if (fence->fd != -1) close(fence->fd);
    return fence;
}

// android::sp<android::Fence>::sp(android::Fence*)
SpFence* _ZN7android2spINS_5FenceEEC1EPS1_(SpFence* sp, NougatFence* fence) {
    sp->ptr = fence;
    if (fence != nullptr) fence->count.fetch_add(1, std::memory_order_relaxed);
    return sp;
}

// android::sp<android::Fence>::~sp(): the last reference deletes the Fence.
SpFence* _ZN7android2spINS_5FenceEED1Ev(SpFence* sp) {
    NougatFence* fence = sp->ptr;
    if (fence != nullptr && fence->count.fetch_sub(1, std::memory_order_acq_rel) == 1) {
        _ZN7android5FenceD1Ev(fence);
        ::operator delete(fence);
    }
    return sp;
}

}  // extern "C"
