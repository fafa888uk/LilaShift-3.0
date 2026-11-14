// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 huamidev
// Runtime entitlement reading adapted from LCSign's LCEntitlementsReader
// (https://sign.lc; no public license stated for LCSign, none asserted here).
// Reimplemented for GestaltX; no LCSign code is bundled.
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface GXEntitlementsReader : NSObject
/// Resolves a usable container from this process's actual signed App Groups.
+ (nullable NSString *)usableAppGroup;
/// All accessible signed groups, so the app can find files sent by its extension.
+ (NSArray<NSString *> *)usableAppGroups;
/// Bounded Mach-O/XML-signature parser, also usable with fixture data.
+ (nullable NSDictionary *)entitlementsInMachOData:(NSData *)data;
@end
NS_ASSUME_NONNULL_END
