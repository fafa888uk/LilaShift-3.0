// SPDX-License-Identifier: GPL-3.0-only
#import "GXIconCacheProbe.h"
#import "GXCustomizationAccess.h"
#import "worse_query.h"
#import <CommonCrypto/CommonDigest.h>
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
static const NSUInteger GXIconEntriesDetailLimit = 32;

@interface GXIconCacheProbe ()
+ (NSDictionary<NSString *, id> *)inspectDirectory:(int)descriptor bundleIdentifier:(NSString *)identifier
                                           rootPath:(nullable NSString *)rootPath;
@end

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

static NSString *GXIconOctalMode(mode_t mode) {
    return [NSString stringWithFormat:@"%o", (unsigned int)mode];
}

static NSString *GXIconFileType(mode_t mode) {
    if (S_ISDIR(mode)) return @"directory";
    if (S_ISREG(mode)) return @"regular";
    if (S_ISLNK(mode)) return @"symlink";
    if (S_ISFIFO(mode)) return @"fifo";
    if (S_ISSOCK(mode)) return @"socket";
    if (S_ISCHR(mode)) return @"character-device";
    if (S_ISBLK(mode)) return @"block-device";
    return @"unknown";
}

static NSString *GXIconSHA256Hex(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

typedef struct {
    NSUInteger entries, bytes, unreadable, budgetSkipped, skippedDirectories;
    BOOL limited;
    int readdirErrno;
} GXIconScan;

// Per-entry diagnostics, capped at GXIconEntriesDetailLimit entries in
// encounter order. Counts and stage totals are uncapped. These collections
// are passed as parameters (like `extensions` and `matches`), not stored
// in GXIconScan, so ARC retains them normally.

// Stage -> count for every entry that produced no content, plus the
// last errno observed for that stage (only when errno != 0).
static void GXIconRecordStage(NSMutableDictionary *stages, NSMutableDictionary *stageErrnos,
                              NSString *stage, int failureErrno) {
    stages[stage] = @([stages[stage] unsignedIntegerValue] + 1);
    if (failureErrno != 0) stageErrnos[stage] = @(failureErrno);
}

static void GXIconAddDetail(NSMutableArray *details, NSDictionary *detail) {
    if (details.count < GXIconEntriesDetailLimit) [details addObject:detail];
}

// One diagnostics entry for a directory entry. Metadata is recorded even
// when the content read was skipped or failed. `stage`/`failureErrno`
// describe the failure, when there is one; `extra` carries stage-specific
// facts such as a symlink target or the stat() second opinion.
static NSDictionary *GXIconEntryDetail(NSString *name, int direntType, const struct stat *metadata,
                                       NSString * _Nullable stage, int failureErrno,
                                       NSDictionary * _Nullable extra) {
    NSMutableDictionary *detail = [NSMutableDictionary dictionary];
    detail[@"name"] = name;
    detail[@"direntType"] = @(direntType);
    if (metadata) {
        detail[@"mode"] = GXIconOctalMode(metadata->st_mode);
        detail[@"fileType"] = GXIconFileType(metadata->st_mode);
        detail[@"size"] = @(metadata->st_size);
        detail[@"uid"] = @(metadata->st_uid);
        detail[@"gid"] = @(metadata->st_gid);
        detail[@"inode"] = @(metadata->st_ino);
    }
    if (stage) {
        detail[@"stage"] = stage;
        detail[@"errno"] = @(failureErrno);
    }
    if (extra) [detail addEntriesFromDictionary:extra];
    return detail;
}

// Reads at most `limit` bytes of a regular file for matching. On failure
// reports the stage and errno through the out parameters. An empty file is
// not a failure (stage stays nil) because there is no prefix to read.
// Stages: "prefixOpen" (openat failed), "prefixFstat" (fstat failed or the
// reopened file is not the same regular file), "prefixRead" (read failed
// or returned no bytes for a non-empty file).
static NSData *GXIconPrefix(int directory, const char *name, const struct stat *indexed, NSUInteger limit,
                            NSString * _Nullable * _Nullable stageOut, int * _Nullable errnoOut) {
    if (stageOut) *stageOut = nil;
    if (errnoOut) *errnoOut = 0;
    int fd = openat(directory, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK);
    if (fd < 0) {
        if (stageOut) *stageOut = @"prefixOpen";
        if (errnoOut) *errnoOut = errno;
        return nil;
    }
    struct stat actual;
    if (fstat(fd, &actual)) {
        int failure = errno;
        close(fd);
        if (stageOut) *stageOut = @"prefixFstat";
        if (errnoOut) *errnoOut = failure;
        return nil;
    }
    if (!S_ISREG(actual.st_mode) || actual.st_ino != indexed->st_ino ||
        actual.st_dev != indexed->st_dev) {
        close(fd);
        if (stageOut) *stageOut = @"prefixFstat";
        if (errnoOut) *errnoOut = 0;
        return nil;
    }
    if (actual.st_size <= 0) { close(fd); return nil; }

    NSUInteger capacity = MIN(limit, (uint64_t)actual.st_size);
    NSMutableData *data = [NSMutableData dataWithLength:capacity];
    size_t count = 0;
    while (count < capacity) {
        ssize_t got = read(fd, (char *)data.mutableBytes + count, capacity - count);
        if (got < 0 && errno == EINTR) continue;
        if (got < 0) {
            int failure = errno;
            close(fd);
            if (stageOut) *stageOut = @"prefixRead";
            if (errnoOut) *errnoOut = failure;
            return nil;
        }
        if (got == 0) break;
        count += (size_t)got;
    }
    close(fd);
    if (!count) {
        if (stageOut) *stageOut = @"prefixRead";
        if (errnoOut) *errnoOut = 0;
        return nil;
    }
    data.length = count;
    return data;
}

static NSString *GXIconFullPath(NSString *rootPath, NSString *relative, NSString *name) {
    NSString *path = rootPath;
    if (relative.length) path = [path stringByAppendingPathComponent:relative];
    return [path stringByAppendingPathComponent:name];
}

static void GXInspectIconDirectory(int fd, NSString *relative, NSData *narrow, NSData *wide,
                                   GXIconScan *scan, NSMutableDictionary *extensions, NSMutableArray *matches,
                                   NSMutableArray *details, NSMutableDictionary *stages,
                                   NSMutableDictionary *stageErrnos,
                                   CFAbsoluteTime deadline, NSString * _Nullable rootPath) {
    // Open an independent directory stream without changing the caller's descriptor offset.
    int iterator = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (iterator < 0) {
        int failure = errno;
        scan->unreadable++;
        GXIconRecordStage(stages, stageErrnos, @"iteratorOpen", failure);
        return;
    }
    DIR *directory = fdopendir(iterator);
    if (!directory) {
        int failure = errno;
        close(iterator);
        scan->unreadable++;
        GXIconRecordStage(stages, stageErrnos, @"iteratorOpen", failure);
        return;
    }
    for (;;) {
        if (scan->entries >= GXIconEntryLimit || CFAbsoluteTimeGetCurrent() >= deadline) {
            scan->limited = YES;
            break;
        }
        errno = 0;
        struct dirent *entry = readdir(directory);
        if (!entry) {
            if (errno) {
                scan->unreadable++;
                scan->readdirErrno = errno;
                GXIconRecordStage(stages, stageErrnos, @"readdir", errno);
            }
            break;
        }
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        scan->entries++;
        @autoreleasepool {
            // A name that cannot decode as UTF-8 has no name to attach
            // diagnostics to; it is counted unreadable and skipped.
            NSString *name = [NSString stringWithUTF8String:entry->d_name];
            if (!name) { scan->unreadable++; continue; }
            struct stat metadata;
            if (fstatat(fd, entry->d_name, &metadata, AT_SYMLINK_NOFOLLOW)) {
                int failure = errno;
                scan->unreadable++;
                GXIconRecordStage(stages, stageErrnos, @"fstatat", failure);
                NSMutableDictionary *extra = [NSMutableDictionary dictionary];
                const struct stat *reported = NULL;
                if (rootPath) {
                    // Second opinion by full path. stat() follows a final
                    // symlink, so symlinks (and unknown types, which may
                    // be symlinks) are checked with lstat() instead; the
                    // target is never followed outside the scanned root.
                    NSString *full = GXIconFullPath(rootPath, relative, name);
                    struct stat second;
                    int secondResult;
                    if (entry->d_type == DT_LNK || entry->d_type == DT_UNKNOWN) {
                        secondResult = lstat(full.fileSystemRepresentation, &second);
                    } else {
                        secondResult = stat(full.fileSystemRepresentation, &second);
                    }
                    int secondErrno = secondResult == 0 ? 0 : errno;
                    extra[@"statErrno"] = @(secondErrno);
                    if (secondResult == 0) {
                        extra[@"statFallback"] = @(YES);
                        metadata = second;
                        reported = &metadata;
                    }
                }
                GXIconAddDetail(details, GXIconEntryDetail(name, entry->d_type, reported, @"fstatat", failure, extra));
                continue;
            }
            if (S_ISDIR(metadata.st_mode)) {
                if (!relative.length && [[NSUUID alloc] initWithUUIDString:name]) {
                    int child = openat(fd, entry->d_name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
                    if (child >= 0) {
                        GXIconAddDetail(details, GXIconEntryDetail(name, entry->d_type, &metadata, nil, 0, nil));
                        GXInspectIconDirectory(child, name, narrow, wide, scan, extensions, matches,
                                               details, stages, stageErrnos, deadline, rootPath);
                        close(child);
                    } else {
                        int failure = errno;
                        scan->unreadable++;
                        GXIconRecordStage(stages, stageErrnos, @"childOpen", failure);
                        GXIconAddDetail(details, GXIconEntryDetail(name, entry->d_type, &metadata, @"childOpen", failure, nil));
                    }
                } else {
                    scan->skippedDirectories++;
                    GXIconAddDetail(details, GXIconEntryDetail(name, entry->d_type, &metadata, nil, 0, nil));
                }
                continue;
            }
            if (!S_ISREG(metadata.st_mode)) {
                // Non-regular entries are never opened or followed. A
                // symlink's target is recorded, never dereferenced.
                NSMutableDictionary *extra = [NSMutableDictionary dictionary];
                if (S_ISLNK(metadata.st_mode)) {
                    char target[1025];
                    ssize_t length = readlinkat(fd, entry->d_name, target, sizeof(target) - 1);
                    if (length >= 0) {
                        target[length] = '\0';
                        NSString *targetString = [NSString stringWithUTF8String:target];
                        if (targetString) {
                            extra[@"target"] = targetString;
                            if ((size_t)length == sizeof(target) - 1) extra[@"targetTruncated"] = @(YES);
                        }
                    } else {
                        extra[@"targetErrno"] = @(errno);
                    }
                }
                GXIconRecordStage(stages, stageErrnos, @"nonRegular", 0);
                GXIconAddDetail(details, GXIconEntryDetail(name, entry->d_type, &metadata, @"nonRegular", 0, extra));
                continue;
            }
            NSString *ext = name.pathExtension.lowercaseString;
            if (![@[@"isdata", @"isindex", @"plist", @"json", @"png", @"cpbitmap", @"car", @"sqlite", @"db"] containsObject:ext]) {
                ext = @"other";
            }
            extensions[ext] = @([extensions[ext] unsignedIntegerValue] + 1);
            BOOL filenameMatch = GXContainsIdentifier([name.stringByDeletingPathExtension dataUsingEncoding:NSUTF8StringEncoding],
                                                      narrow, NO);
            NSData *prefix = nil;
            NSString *prefixStage = nil;
            int prefixErrno = 0;
            BOOL prefixSkipped = NO;
            if (scan->bytes < GXIconReadBudget) {
                prefix = GXIconPrefix(fd, entry->d_name, &metadata, MIN(GXIconPrefixLimit, GXIconReadBudget - scan->bytes),
                                      &prefixStage, &prefixErrno);
                scan->bytes += prefix.length;
                if (!prefix && metadata.st_size > 0) scan->unreadable++;
                if (prefixStage) GXIconRecordStage(stages, stageErrnos, prefixStage, prefixErrno);
            } else {
                scan->budgetSkipped++;
                prefixSkipped = YES;
            }
            BOOL contentMatch = prefix && (GXContainsIdentifier(prefix, narrow, NO) ||
                                           GXContainsIdentifier(prefix, wide, YES));
            NSMutableDictionary *extra = [NSMutableDictionary dictionary];
            if (prefixSkipped) extra[@"prefixSkipped"] = @(YES);
            GXIconAddDetail(details, GXIconEntryDetail(name, entry->d_type, &metadata, prefixStage, prefixErrno, extra));
            if (!(filenameMatch || contentMatch)) continue;
            if (matches.count >= GXIconMatchLimit) { scan->limited = YES; continue; }
            NSString *path = relative.length ? [relative stringByAppendingPathComponent:name] : name;
            NSMutableDictionary *match = [@{@"file": path, @"bytes": @(metadata.st_size), @"inode": @(metadata.st_ino),
                                            @"filenameMatch": @(filenameMatch), @"contentMatch": @(contentMatch)} mutableCopy];
            if (rootPath) match[@"root"] = rootPath;
            if (prefix) match[@"prefixSHA256"] = GXIconSHA256Hex(prefix);
            [matches addObject:match];
        }
    }
    closedir(directory);
}

@implementation GXIconCacheProbe
+ (NSDictionary<NSString *, id> *)inspectDirectory:(int)descriptor bundleIdentifier:(NSString *)identifier {
    return [self inspectDirectory:descriptor bundleIdentifier:identifier rootPath:nil];
}

+ (NSDictionary<NSString *, id> *)inspectDirectory:(int)descriptor bundleIdentifier:(NSString *)identifier
                                           rootPath:(nullable NSString *)rootPath {
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
    NSMutableArray *details = [NSMutableArray array];
    NSMutableDictionary *stages = [NSMutableDictionary dictionary];
    NSMutableDictionary *stageErrnos = [NSMutableDictionary dictionary];
    GXInspectIconDirectory(descriptor, @"", narrow, wide, &scan, extensions, matches,
                           details, stages, stageErrnos,
                           CFAbsoluteTimeGetCurrent() + 4, rootPath);
    NSMutableDictionary *result = [@{@"inode": @(info.st_ino), @"entries": @(scan.entries), @"bytesRead": @(scan.bytes),
             @"unreadable": @(scan.unreadable), @"budgetSkipped": @(scan.budgetSkipped),
             @"skippedDirectories": @(scan.skippedDirectories), @"limited": @(scan.limited),
             @"directoryStat": @{@"mode": GXIconOctalMode(info.st_mode), @"uid": @(info.st_uid),
                                 @"gid": @(info.st_gid), @"inode": @(info.st_ino)},
             @"entriesDetail": details, @"unreadableStages": stages,
             @"stageErrnos": stageErrnos,
             @"extensions": extensions, @"matches": matches} mutableCopy];
    if (scan.readdirErrno != 0) result[@"readdirErrno"] = @(scan.readdirErrno);
    return result;
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
            [result addEntriesFromDictionary:[self inspectDirectory:fd bundleIdentifier:identifier rootPath:root]];
            close(fd);
        }
        if (lease >= 0) worse_query_release(lease);
        [results addObject:result];
    }
    return results;
#endif
}
@end
