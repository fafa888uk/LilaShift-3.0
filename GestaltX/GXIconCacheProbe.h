// SPDX-License-Identifier: GPL-3.0-only
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface GXIconCacheProbe : NSObject
+ (NSArray<NSDictionary<NSString *, id> *> *)inspectBundleIdentifier:(NSString *)identifier
    NS_SWIFT_NAME(inspect(bundleIdentifier:));

// The caller retains ownership of the descriptor. Reports metadata and target matches only.
+ (NSDictionary<NSString *, id> *)inspectDirectory:(int)descriptor bundleIdentifier:(NSString *)identifier
    NS_SWIFT_NAME(inspectDirectory(_:bundleIdentifier:));
@end
NS_ASSUME_NONNULL_END
