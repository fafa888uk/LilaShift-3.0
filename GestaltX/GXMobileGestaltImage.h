// SPDX-License-Identifier: GPL-3.0-only
// Implementation adapts Erosion-CN's MGImageReader `__cfstring` walk (Kianuni,
// https://github.com/Kianuni/Erosion-CN, GPL-3.0); see GXMobileGestaltImage.m.
#import <Foundation/Foundation.h>

// Read-only snapshots of the currently loaded system library's query sections.
FOUNDATION_EXPORT NSDictionary<NSString *, id> * _Nullable GXCopyMobileGestaltImage(void);
