/*
 * android::AudioSystem::setErrorCallback(void (*)(int)).
 *
 * Up to Android 9 AudioSystem kept one error callback and this set it. Since then it
 * keeps a set of them, with addErrorCallback() and removeErrorCallback(), and the old
 * function is gone: rild stops at
 *
 *     dlopen failed: cannot locate symbol "_ZN7android11AudioSystem16setErrorCallbackEPFviE"
 *     referenced by "/system/vendor/lib64/libril-qc-qmi-1.so"
 *
 * and exits. What the RIL does when the callback fires was not looked into.
 *
 * One callback at a time, as the old function had it: setting another replaces the
 * first, and setting none removes it. A null pointer must not reach the set, which
 * calls every entry it holds.
 */

#include <media/AudioSystem.h>

static uintptr_t registered;

extern "C" void _ZN7android11AudioSystem16setErrorCallbackEPFviE(android::audio_error_callback cb) {
    if (registered != 0) {
        android::AudioSystem::removeErrorCallback(registered);
        registered = 0;
    }
    if (cb != nullptr) {
        registered = android::AudioSystem::addErrorCallback(cb);
    }
}
