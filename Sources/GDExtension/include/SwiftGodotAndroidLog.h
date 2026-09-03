//
//  SwiftGodotAndroidLog.h
//
//  Writes to the Android system log, which is where device diagnostics are
//  collected. Swift cannot call the variadic logging function directly.
//

#ifndef SwiftGodotAndroidLog_h
#define SwiftGodotAndroidLog_h

/// Logs `message` at info level under the SwiftGodot tag. No-op outside Android.
void swiftgodot_android_log_info(const char *message);

#endif /* SwiftGodotAndroidLog_h */
