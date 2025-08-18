//
//  JRScanServiceBridge.m
//  IconFinder
//
//  Objective-C bridge implementation that forwards to Swift ScanService
//

#import "JRScanServiceBridge.h"
#import "IconFinder-Swift.h"

@implementation JRScanServiceBridge

+ (void)stop {
    [ScanService.shared stop];
}

+ (void)startScanDeep:(BOOL)deep
              allowed:(NSArray<NSString*> *)allowed
               denied:(NSArray<NSString*> *)denied
      includeExternal:(BOOL)includeExternal
              onBatch:(void (^)(NSArray<NSString*> *batch))onBatch
             onFinish:(void (^)(void))onFinish
{
    [ScanService.shared startScan:deep
                      allowedRoots:allowed
                      deniedRoots:denied
            includeExternalVolumes:includeExternal
                            onBatch:onBatch
                           onFinish:onFinish];
}

@end

