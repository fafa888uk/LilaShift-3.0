// SPDX-License-Identifier: GPL-3.0-only
#import <Foundation/Foundation.h>

// Only available local answers are returned. No identifiers are logged.
FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nonnull GXCopyCurrentDeviceIdentity(void);

// Physical hardware identity from the kernel (`hw.machine` /
// `hw.model`), independent of any MobileGestalt cache. Used by the
// Face ID recovery to verify a backup against the real hardware
// (upstream GestaltX #128, huamidev/GestaltX).
FOUNDATION_EXPORT NSDictionary<NSString *, NSString *> * _Nonnull GXCopyPhysicalHardwareIdentity(void);
