// SPDX-License-Identifier: GPL-3.0-only
// Container identity follows forcequitOS's fsgetpath research; PosterBoard
// targets follow Gester (MIT) and Erosion (GPL-3.0). See GXCustomizationAccess.m
// and Licenses/ThirdPartyNotices.txt for sources and complete licenses.
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface GXCustomizationAccess : NSObject
+ (nullable NSString *)containerForIdentifier:(NSString *)identifier NS_SWIFT_NAME(container(for:));
+ (int64_t)acquirePath:(NSString *)path;
+ (BOOL)openApplication:(NSString *)identifier;
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)launchApplications;
+ (nullable NSString *)launchContainerForIdentifier:(NSString *)identifier NS_SWIFT_NAME(launchContainer(for:));
+ (NSDictionary<NSString *, id> *)launchApplicationInventory:(BOOL)discover;
+ (nullable NSData *)homeScreenIconForIdentifier:(NSString *)identifier NS_SWIFT_NAME(homeScreenIcon(for:));
+ (NSDictionary<NSString *, id> *)verifyLaunchApplication:(NSDictionary<NSString *, id> *)metadata;
@end
NS_ASSUME_NONNULL_END
