// SPDX-License-Identifier: GPL-3.0-only
#import "GXIconCacheProbe.h"
#import "GXCustomizationAccess.h"
#import "worse_query.h"
#import <TargetConditionals.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static const NSUInteger GXIconEntryLimit = 1800;
static const NSUInteger GXIconReadBudget = 24 * 1024 * 1024;
static const NSUInteger GXIconPrefixLimit = 128 * 1024;
static const NSUInteger GXIconMatchLimit = 16;

static BOOL GXIdentifierByte(unsigned char byte) {
    return (byte >= 'A' && byte <= 'Z') || (byte >= 'a' && byte <= 'z') ||
        (byte >= '0' && byte <= '9') || byte == '.' || byte == '-' || byte == '_';
}

static BOOL GXContainsIdentifier(NSData *data, NSData *identifier, BOOL wide) {
    if (identifier.length == 0) return NO;
    const unsigned char *bytes = data.bytes;
    NSRange remaining = NSMakeRange(0, data.length);
    while (remaining.length >= identifier.length) {
        NSRange match = [data rangeOfData:identifier options:0 range:remaining];
        if (match.location == NSNotFound) return NO;
        NSUInteger end = NSMaxRange(match);
        BOOL left = match.location > 0 && GXIdentifierByte(bytes[match.location - 1]);
        if (wide) {
            left = match.location >= 2 && bytes[match.location - 1] == 0 &&
                GXIdentifierByte(bytes[match.location - 2]);
        }
        BOOL right = end < data.length && GXIdentifierByte(bytes[end]) &&
            (!wide || (end + 1 < data.length && bytes[end + 1] == 0));
        if (!left && !right) return YES;
        remaining = NSMakeRange(match.location + 1, data.length - match.location - 1);
    }
    return NO;
}

static NSData *GXIconPrefix(int directory, const char *name, const struct stat *indexed, NSUInteger limit) {
    int fd = openat(directory, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    if (fd < 0) return nil;
    struct stat actual;
    if (fstat(fd, &actual) || !S_ISREG(actual.st_mode) || actual.st_ino != indexed->st_ino ||
        actual.st_dev != indexed->st_dev || actual.st_size <= 0) {
        close(fd);
        return nil;
    }

    NSUInteger capacity = MIN(limit, (uint64_t)actual.st_size);
    NSMutableData *data = [NSMutableData dataWithLength:capacity];
    size_t count = 0;
    while (count < capacity) {
        ssize_t got = read(fd, (char *)data.mutableBytes + count, capacity - count);
        if (got < 0 && errno == EINTR) continue;
        if (got <= 0) break;
        count += (size_t)got;
    }
    close(fd);
    if (!count) return nil;
    data.length = count;
    return data;
}

typedef struct {
    NSUInteger entries, bytes, unreadable, budgetSkipped, skippedDirectories;
    BOOL limited;
} GXIconScan;

static void GXInspectIconDirectory(int fd, NSString *relative, NSData *narrow, NSData *wide,
                                   GXIconScan *scan, NSMutableDictionary *extensions, NSMutableArray *matches,
                                   CFAbsoluteTime deadline) {
    // Open an independent directory stream without changing the caller's descriptor offset.
    int iterator = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (iterator < 0) { scan->unreadable++; return; }
    DIR *directory = fdopendir(iterator);
    if (!directory) { close(iterator); scan->unreadable++; return; }
    for (;;) {
        if (scan->entries >= GXIconEntryLimit || CFAbsoluteTimeGetCurrent() >= deadline) {
            scan->limited = YES;
            break;
        }
        errno = 0;
        struct dirent *entry = readdir(directory);
        if (!entry) { if (errno) scan->unreadable++; break; }
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        scan->entries++;
        @autoreleasepool {
            NSString *name = [NSString stringWithUTF8String:entry->d_name];
            struct stat metadata;
            if (!name || fstatat(fd, entry->d_name, &metadata, AT_SYMLINK_NOFOLLOW)) {
                scan->unreadable++;
                continue;
            }
            if (S_ISDIR(metadata.st_mode)) {
                if (!relative.length && [[NSUUID alloc] initWithUUIDString:name]) {
                    int child = openat(fd, entry->d_name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
                    if (child >= 0) {
                        GXInspectIconDirectory(child, name, narrow, wide, scan, extensions, matches, deadline);
                        close(child);
                    } else {
                        scan->unreadable++;
                    }
                } else {
                    scan->skippedDirectories++;
                }
                continue;
            }
            if (!S_ISREG(metadata.st_mode)) continue;
            NSString *ext = name.pathExtension.lowercaseString;
            if (![@[@"isdata", @"isindex", @"plist", @"json", @"png", @"cpbitmap", @"car", @"sqlite", @"db"] containsObject:ext]) {
                ext = @"other";
            }
            extensions[ext] = @([extensions[ext] unsignedIntegerValue] + 1);
            BOOL filenameMatch = GXContainsIdentifier([name.stringByDeletingPathExtension dataUsingEncoding:NSUTF8StringEncoding],
                                                      narrow, NO);
            NSData *prefix = nil;
            if (scan->bytes < GXIconReadBudget) {
                prefix = GXIconPrefix(fd, entry->d_name, &metadata, MIN(GXIconPrefixLimit, GXIconReadBudget - scan->bytes));
                scan->bytes += prefix.length;
                if (!prefix && metadata.st_size > 0) scan->unreadable++;
            } else {
                scan->budgetSkipped++;
            }
            BOOL contentMatch = prefix && (GXContainsIdentifier(prefix, narrow, NO) ||
                                           GXContainsIdentifier(prefix, wide, YES));
            if (!(filenameMatch || contentMatch)) continue;
            if (matches.count >= GXIconMatchLimit) { scan->limited = YES; continue; }
            NSString *path = relative.length ? [relative stringByAppendingPathComponent:name] : name;
            [matches addObject:@{@"file": path, @"bytes": @(metadata.st_size), @"inode": @(metadata.st_ino),
                                 @"filenameMatch": @(filenameMatch), @"contentMatch": @(contentMatch)}];
        }
    }
    closedir(directory);
}

@implementation GXIconCacheProbe
+ (NSDictionary<NSString *, id> *)inspectDirectory:(int)descriptor bundleIdentifier:(NSString *)identifier {
    NSData *narrow = [identifier dataUsingEncoding:NSUTF8StringEncoding];
    NSData *wide = [identifier dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
    if (narrow.length < 3 || narrow.length > 255 || ![identifier containsString:@"."]) return @{};
    const unsigned char *bytes = narrow.bytes;
    for (NSUInteger i = 0; i < narrow.length; i++) if (!GXIdentifierByte(bytes[i])) return @{};

    struct stat info;
    if (fstat(descriptor, &info) || !S_ISDIR(info.st_mode)) return @{};
    GXIconScan scan = {0};
    NSMutableDictionary *extensions = [NSMutableDictionary dictionary];
    NSMutableArray *matches = [NSMutableArray array];
    GXInspectIconDirectory(descriptor, @"", narrow, wide, &scan, extensions, matches,
                           CFAbsoluteTimeGetCurrent() + 4);
    return @{@"inode": @(info.st_ino), @"entries": @(scan.entries), @"bytesRead": @(scan.bytes),
             @"unreadable": @(scan.unreadable), @"budgetSkipped": @(scan.budgetSkipped),
             @"skippedDirectories": @(scan.skippedDirectories), @"limited": @(scan.limited),
             @"extensions": extensions, @"matches": matches};
}

+ (NSArray<NSDictionary<NSString *, id> *> *)inspectBundleIdentifier:(NSString *)identifier {
#if TARGET_OS_SIMULATOR
    return @[];
#else
    // Historically reported cache location, probed as a candidate for this build.
    NSString *group = @"/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.lsd.iconscache";
    NSMutableArray *results = [NSMutableArray array];
    NSArray<NSString *> *roots = @[[group stringByAppendingPathComponent:@"Library/Caches/com.apple.IconsCache"],
                                  @"/private/var/mobile/Library/Caches/com.apple.IconsCache"];
    for (NSString *root in roots) {
        int64_t lease = -1;
        int fd = open(root.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
        int failure = fd < 0 ? errno : 0;
        if ((failure == EACCES || failure == EPERM) && [root hasPrefix:group]) {
            lease = [GXCustomizationAccess acquirePath:group];
            if (lease >= 0) {
                fd = open(root.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
                failure = fd < 0 ? errno : 0;
            }
        }
        NSMutableDictionary *result = [@{@"path": root, @"open": @(fd >= 0), @"errno": @(failure),
                                        @"extensionGranted": @(lease >= 0)} mutableCopy];
        if (fd >= 0) {
            [result addEntriesFromDictionary:[self inspectDirectory:fd bundleIdentifier:identifier]];
            close(fd);
        }
        if (lease >= 0) worse_query_release(lease);
        [results addObject:result];
    }
    return results;
#endif
}
@end
