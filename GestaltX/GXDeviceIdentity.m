// SPDX-License-Identifier: GPL-3.0-only
#import "GXDeviceIdentity.h"
#import <dlfcn.h>
#import <sys/sysctl.h>
#import <TargetConditionals.h>

NSDictionary<NSString *, id> *GXCopyCurrentDeviceIdentity(void) {
#if TARGET_OS_SIMULATOR
    return @{};
#else
    typedef CFPropertyListRef (*CopyAnswer)(CFStringRef);
    void *library = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY | RTLD_LOCAL);
    CopyAnswer copy = library ? (CopyAnswer)dlsym(library, "MGCopyAnswer") : NULL;
    NSMutableDictionary *identity = [NSMutableDictionary dictionary];
    if (copy) {
        for (NSString *key in @[@"UniqueDeviceID", @"SerialNumber", @"UniqueChipID"]) {
            CFPropertyListRef answer = copy((__bridge CFStringRef)key);
            if (answer) {
                id value = CFBridgingRelease(answer);
                if ([value isKindOfClass:NSString.class] || [value isKindOfClass:NSNumber.class]) identity[key] = value;
            }
        }
    }
    if (library) dlclose(library);
    return identity;
#endif
}

NSDictionary<NSString *, NSString *> *GXCopyPhysicalHardwareIdentity(void) {
#if TARGET_OS_SIMULATOR
    return @{};
#else
    NSMutableDictionary<NSString *, NSString *> *identity = [NSMutableDictionary dictionary];
    size_t size = 0;
    if (sysctlbyname("hw.machine", NULL, &size, NULL, 0) == 0 && size > 0) {
        char *buffer = malloc(size);
        if (buffer && sysctlbyname("hw.machine", buffer, &size, NULL, 0) == 0) {
            identity[@"hw.machine"] = [NSString stringWithUTF8String:buffer];
        }
        free(buffer);
    }
    size = 0;
    if (sysctlbyname("hw.model", NULL, &size, NULL, 0) == 0 && size > 0) {
        char *buffer = malloc(size);
        if (buffer && sysctlbyname("hw.model", buffer, &size, NULL, 0) == 0) {
            identity[@"hw.model"] = [NSString stringWithUTF8String:buffer];
        }
        free(buffer);
    }
    return identity;
#endif
}
