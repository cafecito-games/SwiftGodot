//
//  SwiftGodotAndroidLog.c
//

#include "SwiftGodotAndroidLog.h"

#if defined(__ANDROID__)
#include <android/log.h>

void swiftgodot_android_log_info(const char *message) {
    __android_log_print(ANDROID_LOG_INFO, "SwiftGodot", "%s", message);
}
#else
void swiftgodot_android_log_info(const char *message) {
    (void)message;
}
#endif
