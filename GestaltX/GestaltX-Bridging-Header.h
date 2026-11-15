// SPDX-License-Identifier: GPL-3.0-only
//
//  GestaltX-Bridging-Header.h
//  GestaltX
//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//  It re-exports the GPL-licensed Obj-C headers below (worse_query is GPL-3.0-or-later;
//  the rest are GPL-3.0-only) into Swift.
//

#include "worse_query.h"

#import "GXEntitlementsReader.h"

#import "GXMobileGestaltImage.h"

#import "GXLiveGestaltProbe.h"

#import "GXDeviceIdentity.h"
#import "GXCustomizationAccess.h"
#import "GXLaunchServicesDatabase.h"
