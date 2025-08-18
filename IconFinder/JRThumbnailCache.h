//
//  JRThumbnailCache.h
//  IconFinder
//
//  Simple async thumbnail cache to speed up collection view scrolling.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface JRThumbnailCache : NSObject
+ (instancetype)shared;
- (void)thumbnailForPath:(NSString *)path
                     size:(CGSize)size
               completion:(void (^)(NSImage * _Nullable image))completion;
- (void)clear;
@end

NS_ASSUME_NONNULL_END
