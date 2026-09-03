//
//  SwiftGodotConcurrencyHooks.c
//
//  The Swift runtime's hook variables hold function pointers with the Swift calling
//  convention. Swift itself cannot form those pointers from ordinary functions, but
//  clang can with the swiftcall attribute, so the hooks are C trampolines that ask
//  Swift for the decision.
//

#include "SwiftGodotConcurrencyHooks.h"

#if defined(__ANDROID__)

#include <android/log.h>
#include <dlfcn.h>
#include <stdint.h>

#define SWIFTGODOT_SWIFTCALL __attribute__((swiftcall))

/// Mirrors the runtime's SerialExecutorRef: an object identity and an implementation word.
typedef struct {
    void *identity;
    uintptr_t implementation;
} SwiftGodotSerialExecutorRef;

typedef SWIFTGODOT_SWIFTCALL void (*SwiftGodotCheckIsolatedOriginal)(SwiftGodotSerialExecutorRef executor);
typedef SWIFTGODOT_SWIFTCALL void (*SwiftGodotCheckIsolatedHook)(SwiftGodotSerialExecutorRef executor, SwiftGodotCheckIsolatedOriginal original);
typedef SWIFTGODOT_SWIFTCALL int8_t (*SwiftGodotIsIsolatingOriginal)(SwiftGodotSerialExecutorRef executor);
typedef SWIFTGODOT_SWIFTCALL int8_t (*SwiftGodotIsIsolatingHook)(SwiftGodotSerialExecutorRef executor, SwiftGodotIsIsolatingOriginal original);
typedef SWIFTGODOT_SWIFTCALL void (*SwiftGodotEnqueueMainOriginal)(void *job);
typedef SWIFTGODOT_SWIFTCALL void (*SwiftGodotEnqueueMainHook)(void *job, SwiftGodotEnqueueMainOriginal original);

/// Implemented in Swift. True when `identity` is the main actor's executor and the caller is on the engine thread.
extern bool swiftgodot_main_actor_owns_current_thread(void *identity);
/// Implemented in Swift. Holds `job` until the engine thread drains main-actor jobs.
extern void swiftgodot_enqueue_main_actor_job(void *job);
/// Logs the first hook that made a decision, so the device log shows the hooks are live.
static void swiftgodot_report_first_hook_hit(const char *hook) {
    static bool reported = false;
    if (reported) {
        return;
    }
    reported = true;
    __android_log_print(ANDROID_LOG_INFO, "SwiftGodot", "main actor bound to the engine thread (first hook hit: %s)", hook);
}

static SWIFTGODOT_SWIFTCALL int8_t swiftgodot_is_isolating_current_context(SwiftGodotSerialExecutorRef executor, SwiftGodotIsIsolatingOriginal original) {
    if (swiftgodot_main_actor_owns_current_thread(executor.identity)) {
        swiftgodot_report_first_hook_hit("isIsolatingCurrentContext");
        return 1;
    }
    return original(executor);
}

static SWIFTGODOT_SWIFTCALL void swiftgodot_check_isolated(SwiftGodotSerialExecutorRef executor, SwiftGodotCheckIsolatedOriginal original) {
    if (swiftgodot_main_actor_owns_current_thread(executor.identity)) {
        swiftgodot_report_first_hook_hit("checkIsolated");
        return;
    }
    original(executor);
}

static SWIFTGODOT_SWIFTCALL void swiftgodot_enqueue_main_executor(void *job, SwiftGodotEnqueueMainOriginal original) {
    (void)original;
    swiftgodot_enqueue_main_actor_job(job);
}

const char *swiftgodot_install_concurrency_hooks(void) {
    void *runtime = dlopen("libswift_Concurrency.so", RTLD_NOW | RTLD_NOLOAD);
    if (runtime == NULL) {
        return "libswift_Concurrency.so";
    }

    SwiftGodotIsIsolatingHook *isIsolatingSlot = dlsym(runtime, "swift_task_isIsolatingCurrentContext_hook");
    if (isIsolatingSlot == NULL) {
        return "swift_task_isIsolatingCurrentContext_hook";
    }
    SwiftGodotCheckIsolatedHook *checkIsolatedSlot = dlsym(runtime, "swift_task_checkIsolated_hook");
    if (checkIsolatedSlot == NULL) {
        return "swift_task_checkIsolated_hook";
    }
    SwiftGodotEnqueueMainHook *enqueueMainSlot = dlsym(runtime, "swift_task_enqueueMainExecutor_hook");
    if (enqueueMainSlot == NULL) {
        return "swift_task_enqueueMainExecutor_hook";
    }

    *isIsolatingSlot = swiftgodot_is_isolating_current_context;
    *checkIsolatedSlot = swiftgodot_check_isolated;
    *enqueueMainSlot = swiftgodot_enqueue_main_executor;
    return NULL;
}

#else

const char *swiftgodot_install_concurrency_hooks(void) {
    return "unsupported platform";
}

#endif
