//
//  JRThumbnailCache.m
//  IconFinder
//
//  Async thumbnail cache using NSCache and background generation. Uses
//  QuickLookThumbnailing when available; falls back to NSImage loading.
//

#import "JRThumbnailCache.h"

@interface JRThumbnailCache ()
@property(nonatomic, strong) NSCache *memory;
@property(nonatomic, strong) dispatch_queue_t workQueue;
@end

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

- (void)thumbnailForPath:(NSString *)path
                     size:(CGSize)size
               completion:(void (^)(NSImage * _Nullable))completion {
  if (!path) { dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); }); return; }
  NSString *key = [self keyForPath:path size:size];
  NSImage *cached = [self.memory objectForKey:key];
  if (cached) { dispatch_async(dispatch_get_main_queue(), ^{ completion(cached); }); return; }

  dispatch_async(self.workQueue, ^{
    NSImage *result = nil;
    NSURL *url = [NSURL fileURLWithPath:path];
    // Load image and downscale to thumbnail size; fall back to file icon
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
    if (result) { [self.memory setObject:result forKey:key]; }
    dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
  });
}

- (void)clear { [self.memory removeAllObjects]; }
@end
