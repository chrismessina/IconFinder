//
//  JRThumbnailCache.m
//  IconFinder
//
//  Async thumbnail cache using NSCache and background generation. Uses
//  QuickLookThumbnailing when available; falls back to NSImage loading.
//

#import "JRThumbnailCache.h"
#import <QuickLookThumbnailing/QuickLookThumbnailing.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface JRThumbnailCache ()
@property(nonatomic, strong) NSCache *memory;
@property(nonatomic, strong) dispatch_queue_t workQueue;
@end

static inline NSString *JRThumbCacheDirectory(void) {
  NSArray<NSURL *> *urls = [[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask];
  NSURL *base = urls.firstObject;
  NSURL *dir = [base URLByAppendingPathComponent:@"net.joerhodes.IconFinder/Thumbnails" isDirectory:YES];
  [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
  return dir.path;
}

static inline NSString *JRMD5String(NSString *input) {
  // Cheap hash to create stable filenames; avoid CommonCrypto addition by using built-in hashing
  NSUInteger h = input.hash;
  return [NSString stringWithFormat:@"%08lx", (unsigned long)h];
}

@implementation JRThumbnailCache

+ (instancetype)shared {
  static JRThumbnailCache *s; static dispatch_once_t once;
  dispatch_once(&once, ^{ s = [JRThumbnailCache new]; });
  return s;
}

- (instancetype)init {
  if ((self = [super init])) {
    _memory = [NSCache new];
    _memory.countLimit = 500; // tuneable
    _workQueue = dispatch_queue_create("net.joerhodes.IconFinder.thumbcache",
                                       DISPATCH_QUEUE_CONCURRENT);
  }
  return self;
}

- (NSString *)keyForPath:(NSString *)path size:(CGSize)size {
  return [NSString stringWithFormat:@"%@:%dx%d", path, (int)size.width, (int)size.height];
}

- (NSString *)diskPathForKey:(NSString *)key {
  NSString *file = [JRMD5String(key) stringByAppendingPathExtension:@"png"];
  return [JRThumbCacheDirectory() stringByAppendingPathComponent:file];
}

- (void)thumbnailForPath:(NSString *)path
                     size:(CGSize)size
               completion:(void (^)(NSImage * _Nullable))completion {
  if (!path) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); }); return; }
  NSString *key = [self keyForPath:path size:size];
  NSImage *cached = [self.memory objectForKey:key];
  if (cached) { dispatch_async(dispatch_get_main_queue(), ^{ completion(cached); }); return; }
  // Check disk
  NSString *disk = [self diskPathForKey:key];
  if ([[NSFileManager defaultManager] fileExistsAtPath:disk]) {
    NSImage *diskImg = [[NSImage alloc] initWithContentsOfFile:disk];
    if (diskImg) {
      [self.memory setObject:diskImg forKey:key];
      dispatch_async(dispatch_get_main_queue(), ^{ completion(diskImg); });
      return;
    }
  }

  dispatch_async(self.workQueue, ^{
    __block NSImage *result = nil;
    NSURL *url = [NSURL fileURLWithPath:path];
    if (@available(macOS 11.0, *)) {
      CGFloat scale = NSScreen.mainScreen.backingScaleFactor ?: 2.0;
      QLThumbnailGenerationRequest *request = [[QLThumbnailGenerationRequest alloc] initWithFileAtURL:url size:size scale:scale representationTypes:QLThumbnailGenerationRequestRepresentationTypeAll];
      [[QLThumbnailGenerator sharedGenerator] generateBestRepresentationForRequest:request completionHandler:^(QLThumbnailRepresentation * _Nullable representation, NSError * _Nullable error) {
        if (representation) {
          result = representation.NSImage;
        }
        if (!result) {
          // Fallback path if Quick Look fails
          NSImage *full = [[NSImage alloc] initWithContentsOfURL:url];
          if (!full) { full = [[NSWorkspace sharedWorkspace] iconForFile:path]; }
          if (full) {
            NSImage *thumb = [[NSImage alloc] initWithSize:size];
            [thumb lockFocus];
            [full drawInRect:NSMakeRect(0, 0, size.width, size.height)
                     fromRect:NSZeroRect
                    operation:NSCompositingOperationSourceOver
                     fraction:1.0
               respectFlipped:YES
                        hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
            [thumb unlockFocus];
            result = thumb;
          }
        }
        if (result) {
          [self.memory setObject:result forKey:key];
          // Persist to disk (PNG)
          CGImageRef cgRef = [result CGImageForProposedRect:NULL context:nil hints:nil];
          if (cgRef) {
            NSURL *outURL = [NSURL fileURLWithPath:[self diskPathForKey:key]];
CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)outURL, (__bridge CFStringRef)UTTypePNG.identifier, 1, NULL);
            if (dest) {
              CGImageDestinationAddImage(dest, cgRef, NULL);
              CGImageDestinationFinalize(dest);
              CFRelease(dest);
            }
          }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
      }];
    } else {
      // Pre-11 fallback: manual downscale
      NSImage *full = [[NSImage alloc] initWithContentsOfURL:url];
      if (!full) { full = [[NSWorkspace sharedWorkspace] iconForFile:path]; }
      if (full) {
        result = [[NSImage alloc] initWithSize:size];
        [result lockFocus];
        [full drawInRect:NSMakeRect(0, 0, size.width, size.height)
                 fromRect:NSZeroRect
                operation:NSCompositingOperationSourceOver
                 fraction:1.0
           respectFlipped:YES
                    hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
        [result unlockFocus];
      }
      if (result) {
        [self.memory setObject:result forKey:key];
        // Persist to disk
        CGImageRef cgRef = [result CGImageForProposedRect:NULL context:nil hints:nil];
        if (cgRef) {
          NSURL *outURL = [NSURL fileURLWithPath:[self diskPathForKey:key]];
CGImageDestinationRef dest = CGImageDestinationCreateWithURL((__bridge CFURLRef)outURL, (__bridge CFStringRef)UTTypePNG.identifier, 1, NULL);
          if (dest) {
            CGImageDestinationAddImage(dest, cgRef, NULL);
            CGImageDestinationFinalize(dest);
            CFRelease(dest);
          }
        }
      }
      dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
    }
  });
}

- (void)prefetchThumbnailForPath:(NSString *)path size:(CGSize)size {
  [self thumbnailForPath:path size:size completion:^(__unused NSImage * _Nullable image) {
    // no-op; warms caches
  }];
}

- (void)clear { [self.memory removeAllObjects]; }
@end
