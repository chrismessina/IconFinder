//
//  JRScanServiceBridge.h
//  IconFinder
//
//  Objective-C bridge for calling Swift ScanService from ObjC files
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface JRScanServiceBridge : NSObject
+ (void)stop;
+ (void)startScanDeep:(BOOL)deep
              allowed:(NSArray<NSString*> *)allowed
               denied:(NSArray<NSString*> *)denied
      includeExternal:(BOOL)includeExternal
              onBatch:(void (^)(NSArray<NSString*> *batch))onBatch
             onFinish:(void (^)(void))onFinish;
@end

NS_ASSUME_NONNULL_END

