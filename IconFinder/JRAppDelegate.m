//
//  JRAppDelegate.m
//  IconFinder
//
//  Created by Joe on 6/24/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "JRAppDelegate.h"
#import "JRConstants.h"
#import "JRDatabase.h"
#import "JRImageCollectionViewItemViewController.h"
#import "JRScanServiceBridge.h"
#import <CommonCrypto/CommonCrypto.h>
#import <objc/message.h>

@class ScannedItem;

@interface JRAppDelegate ()

@property(strong) NSMutableArray<ScannedItem *> *imagePaths;
@property(assign) IBOutlet NSSegmentedControl *filterSegment;
@property(strong) NSMutableSet *filters;
@property(strong) NSPredicate *filterPredicate;
@property(readonly) NSMutableArray<ScannedItem *> *filteredImagePaths;
@property(strong) NSTask *findTask; // legacy; no longer used directly

// UI update coalescing during scans
@property(strong) NSTimer *uiCoalesceTimer;
@property(assign) NSUInteger pendingAdds;
@property(assign) NSUInteger lastFilteredCount;

// Dedupe support
@property(assign) BOOL hideDuplicates;
@property(strong) NSMutableDictionary<NSString *, NSString *>
    *pathToHash; // path -> sha256 hex
@property(strong) NSMutableSet
    *seenHashes; // hashes observed this run when hideDuplicates == YES
@property(strong) dispatch_queue_t hashQueue; // serial queue for hashing work

// Settings
@property(strong) id settingsController;
@property(strong) NSTimer *rescanTimer;

@end

@implementation JRAppDelegate

// Disable old-style automatic window restoration to avoid
// restoreWindowWithIdentifier warnings
- (BOOL)applicationShouldRestoreApplicationState:(NSApplication *)app {
  return NO;
}

#pragma mark - CollectionView DataSource/Delegate

- (NSInteger)numberOfSectionsInCollectionView:
    (NSCollectionView *)collectionView {
  return 1;
}
- (NSInteger)collectionView:(NSCollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section {
  return [[self filteredImagePaths] count];
}
- (NSCollectionViewItem *)collectionView:(NSCollectionView *)collectionView
     itemForRepresentedObjectAtIndexPath:(NSIndexPath *)indexPath {
  static NSString *const ident = @"JRImageItem";
  NSCollectionViewItem *item =
      [collectionView makeItemWithIdentifier:ident forIndexPath:indexPath];
  NSArray *paths = [self filteredImagePaths];
  if (indexPath.item < [paths count]) {
    item.representedObject = paths[indexPath.item];
  }
  return item;
}

- (void)flushCoalescedUIUpdates {
  if (self.pendingAdds > 0) {
    NSUInteger newCount = [[self filteredImagePaths] count];
    if (self.collectionView && newCount >= self.lastFilteredCount) {
      NSMutableSet<NSIndexPath *> *toInsert = [NSMutableSet set];
      for (NSUInteger i = self.lastFilteredCount; i < newCount; i++) {
        NSIndexPath *ip = [NSIndexPath indexPathForItem:i inSection:0];
        [toInsert addObject:ip];
      }
      self.lastFilteredCount = newCount;
      NSSet<NSIndexPath *> *insertSet = [toInsert copy];
      [self.collectionView
          performBatchUpdates:^{
            [self.collectionView insertItemsAtIndexPaths:insertSet];
          }
            completionHandler:nil];
    } else {
      self.lastFilteredCount = newCount;
      [self.collectionView reloadData];
    }
    self.pendingAdds = 0;
  }
  [self.uiCoalesceTimer invalidate];
  self.uiCoalesceTimer = nil;
}

- (void)startLaunchScanShowingProgress:(BOOL)showProgress {
  [self findImagesShowingProgress:showProgress];
}

@synthesize window = _window;
@synthesize imagePaths;
@synthesize filterSegment;
@synthesize filters;
@synthesize filterPredicate;
@synthesize findTask;
@dynamic filteredImagePaths;

static NSArray *imageTypes;

+ (void)initialize {
  imageTypes = [NSArray arrayWithObjects:@"jpeg", @"jpg", @"gif", @"png",
                                         @"icns", @"tiff", @"pdf", nil];
}

+ (NSSet *)keyPathsForValuesAffectingFilterPredicate {
  return [NSSet setWithObjects:@"filters", nil];
}

+ (NSSet *)keyPathsForValuesAffectingImagePaths {
  return [NSSet setWithObjects:@"filterPredicate", nil];
}
+ (NSSet *)keyPathsForValuesAffectingFilteredImagePaths {
  return [NSSet setWithObjects:@"filterPredicate", @"imagePaths", nil];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
  NSFileManager *fm = [NSFileManager defaultManager];

  // Create hashing queue (serial)
  self.hashQueue = dispatch_queue_create("com.joe.iconfinder.hash-queue",
                                         DISPATCH_QUEUE_SERIAL);

  // Configure modern collection view layout and registration
  if (self.collectionView) {
    NSCollectionViewFlowLayout *layout =
        [[NSCollectionViewFlowLayout alloc] init];
    // Height needs to accommodate: top(6) + image(width-12), label(~17) +
    // spacers(4+6) With width 100 -> image ~88, total ~121; use 130 to avoid
    // conflicts
    layout.itemSize = NSMakeSize(100, 130);
    layout.minimumInteritemSpacing = 8;
    layout.minimumLineSpacing = 8;
    layout.sectionInset = NSEdgeInsetsMake(8, 8, 8, 8);
    self.collectionView.collectionViewLayout = layout;
    self.collectionView.dataSource = self;
    self.collectionView.delegate = self;
    self.collectionView.selectable = YES;
    [self.collectionView
                registerClass:[JRImageCollectionViewItemViewController class]
        forItemWithIdentifier:@"JRImageItem"];
  }
  // Observe settings changes
  [[NSNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector(settingsDidChange:)
             name:JRAppSettingsDidChangeNotification
           object:nil];
  self.filters = [NSMutableSet set];
  self.filterPredicate = [NSPredicate predicateWithValue:YES];
  self.hideDuplicates =
      [[NSUserDefaults standardUserDefaults] boolForKey:@"HideDuplicates"];

  // Load hash cache if present
  if ([fm fileExistsAtPath:[self hashCacheFilePath]]) {
    NSDictionary *cache =
        [NSDictionary dictionaryWithContentsOfFile:[self hashCacheFilePath]];
    self.pathToHash = [cache mutableCopy];
  } else {
    self.pathToHash = [NSMutableDictionary dictionary];
  }

  // Load any cached results quickly so UI can show something immediately
  // Initialize database and load any previously stored results
  [[JRDatabase shared] setup];
  NSArray<ScannedItem *> *persisted = [[JRDatabase shared] fetchAllItems];
  if (persisted.count > 0) {
    self.imagePaths = [persisted mutableCopy];
  } else {
    self.imagePaths = [NSMutableArray array];
  }
  self.lastFilteredCount = [[self filteredImagePaths] count];
  [self.collectionView reloadData];

  [self filterChanged:self.filterSegment];

  // Always kick off a scan at launch. For fast scans, don't show a
  // blocking/progress alert.
  BOOL deepScan =
      [[NSUserDefaults standardUserDefaults] boolForKey:@"DeepScanEnabled"];
  [self startLaunchScanShowingProgress:deepScan];
}

- (void)findImagesShowingProgress:(BOOL)showProgress {
  BOOL deepScan =
      [[NSUserDefaults standardUserDefaults] boolForKey:@"DeepScanEnabled"];
  // Scan everywhere by default (root), unless user specifies allowed roots.
  NSArray *allowed =
      [[NSUserDefaults standardUserDefaults] arrayForKey:@"AllowedRoots"] ?: @[ @"/" ];
  // By default, do not exclude any specific paths (users can add exclusions).
  NSArray *denied =
      [[NSUserDefaults standardUserDefaults] arrayForKey:@"DeniedRoots"] ?: @[];
  // Default: exclude external volumes unless explicitly included
  id includeObj = [[NSUserDefaults standardUserDefaults] objectForKey:@"IncludeExternalVolumes"];
  BOOL includeExternal = includeObj ? [[NSUserDefaults standardUserDefaults] boolForKey:@"IncludeExternalVolumes"] : NO;

  __block NSAlert *searchingAlert = nil;
  __block NSProgressIndicator *progIndicator = nil;
  if (showProgress || deepScan) {
    searchingAlert = [[NSAlert alloc] init];
    searchingAlert.messageText = @"Searching your Mac for images";
    searchingAlert.informativeText =
        deepScan ? @"Deep Scan walks the filesystem and may take longer."
                 : @"Using Spotlight for a fast, indexed search.";
    [searchingAlert addButtonWithTitle:@"Stop"];
    progIndicator =
        [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, 200, 32)];
    [progIndicator setIndeterminate:YES];
    [progIndicator setDisplayedWhenStopped:NO];
    [searchingAlert setAccessoryView:progIndicator];
    [searchingAlert beginSheetModalForWindow:self.window
                           completionHandler:^(NSModalResponse returnCode) {
                             // User pressed Stop
                             if (returnCode == NSAlertFirstButtonReturn) {
                               [JRScanServiceBridge stop];
                             }
                           }];
    [progIndicator startAnimation:self];
  }

  // Reset current results so we don't duplicate entries when rescanning
  self.imagePaths = [NSMutableArray array];
  [[JRDatabase shared] clearAll];
  self.lastFilteredCount = 0;
  [self.collectionView reloadData];

  // Prepare seen hash set if de-dup is enabled
  if (self.hideDuplicates) {
    self.seenHashes = [NSMutableSet set];
  } else {
    self.seenHashes = nil;
  }

  __unsafe_unretained typeof(self) weakSelf = self;
  [JRScanServiceBridge startScanDeep:deepScan
      allowed:allowed
      denied:denied
      includeExternal:includeExternal
      onBatch:^(NSArray<ScannedItem *> *batch) {
        __strong typeof(weakSelf) selfStrong = weakSelf;
        if (!selfStrong)
          return;

        if (selfStrong.hideDuplicates) {
          // Hash in background, then append unique on main
          for (id item in batch) {
            dispatch_async(selfStrong.hashQueue, ^{
              NSString *path = [item valueForKey:@"path"];
              NSString *hash = [selfStrong sha256ForFileAtPath:path];
              if (hash == nil) {
                // If we couldn't hash (e.g., unreadable), treat as unique
                dispatch_async(dispatch_get_main_queue(), ^{
                  [selfStrong.imagePaths addObject:item];
                  [[JRDatabase shared] insertItems:@[ item ]];
                  selfStrong.pendingAdds += 1;
                  if (!selfStrong.uiCoalesceTimer) {
                    selfStrong.uiCoalesceTimer =
                        [NSTimer scheduledTimerWithTimeInterval:0.2
                                                         target:selfStrong
                                                       selector:@selector
                                                       (flushCoalescedUIUpdates)
                                                       userInfo:nil
                                                        repeats:NO];
                  }
                  if (searchingAlert) {
                    searchingAlert.informativeText = [NSString
                        stringWithFormat:@"%ld images found.",
                                         (long)[selfStrong.imagePaths count]];
                  }
                });
                return;
              }
              dispatch_async(dispatch_get_main_queue(), ^{
                if (![selfStrong.seenHashes containsObject:hash]) {
                  [selfStrong.seenHashes addObject:hash];
                  [item setValue:hash forKey:@"sha256"];
                  [selfStrong.imagePaths addObject:item];
                  [[JRDatabase shared] insertItems:@[ item ]];
                  selfStrong.pendingAdds += 1;
                  if (!selfStrong.uiCoalesceTimer) {
                    selfStrong.uiCoalesceTimer =
                        [NSTimer scheduledTimerWithTimeInterval:0.2
                                                         target:selfStrong
                                                       selector:@selector
                                                       (flushCoalescedUIUpdates)
                                                       userInfo:nil
                                                        repeats:NO];
                  }
                  if (searchingAlert) {
                    searchingAlert.informativeText = [NSString
                        stringWithFormat:@"%ld images found.",
                                         (long)[selfStrong.imagePaths count]];
                  }
                }
              });
            });
          }
        } else {
          // No de-dup: append directly
          NSUInteger added = 0;
          for (id it in batch) {
            [selfStrong.imagePaths addObject:it];
            added++;
          }
          [[JRDatabase shared] insertItems:batch];
          if (searchingAlert) {
            searchingAlert.informativeText =
                [NSString stringWithFormat:@"%ld images found.",
                                           (long)[selfStrong.imagePaths count]];
          }
          if (added > 0) {
            selfStrong.pendingAdds += added;
            if (!selfStrong.uiCoalesceTimer) {
              selfStrong.uiCoalesceTimer =
                  [NSTimer scheduledTimerWithTimeInterval:0.2
                                                   target:selfStrong
                                                 selector:@selector
                                                 (flushCoalescedUIUpdates)
                                                 userInfo:nil
                                                  repeats:NO];
            }
          }
        }
      }
      onFinish:^{
        __strong typeof(weakSelf) selfStrong = weakSelf;
        if (!selfStrong)
          return;
        [selfStrong flushCoalescedUIUpdates];
        if (searchingAlert) {
          [[searchingAlert window] orderOut:selfStrong];
        }
        // Final UI sync
        [selfStrong flushCoalescedUIUpdates];
      }];
}

- (void)writeImagePaths {
  NSFileManager *fm = [NSFileManager defaultManager];
  BOOL isDirectory = NO;
  NSString *appSupport =
      [NSHomeDirectory() stringByAppendingPathComponent:
                             @"/Library/Application Support/IconFinder"];

  if (!([fm fileExistsAtPath:appSupport isDirectory:&isDirectory] &&
        isDirectory)) {
    [fm createDirectoryAtPath:appSupport
        withIntermediateDirectories:YES
                         attributes:nil
                              error:nil];
  }

  NSString *imagePathsFile =
      [appSupport stringByAppendingPathComponent:@"imagePaths.plist"];
  [self.imagePaths writeToFile:imagePathsFile atomically:YES];
  // Persist hash cache as well
  if (self.pathToHash) {
    [self.pathToHash writeToFile:[self hashCacheFilePath] atomically:YES];
  }
}

- (NSString *)imagesPlistFilePath {
  return [NSHomeDirectory()
      stringByAppendingPathComponent:
          @"/Library/Application Support/IconFinder/imagePaths.plist"];
}

- (NSString *)hashCacheFilePath {
  return [NSHomeDirectory()
      stringByAppendingPathComponent:
          @"/Library/Application Support/IconFinder/hashCache.plist"];
}

- (NSMutableArray<ScannedItem *> *)filteredImagePaths {
  NSArray *base =
      [self.imagePaths filteredArrayUsingPredicate:self.filterPredicate];
  if (!self.hideDuplicates) {
    return [base mutableCopy];
  }
  // Hide exact duplicates by SHA-256; keep first occurrence
  NSMutableArray<ScannedItem *> *result =
      [NSMutableArray arrayWithCapacity:[base count]];
  NSMutableSet *seen = [NSMutableSet set];
  for (id item in base) {
    NSString *hash = [item valueForKey:@"sha256"];
    if (!hash) {
      NSString *path = [item valueForKey:@"path"];
      hash = [self sha256ForFileAtPath:path];
    }
    if (hash == nil) {
      [result addObject:item];
      continue;
    }
    if (![seen containsObject:hash]) {
      [seen addObject:hash];
      [result addObject:item];
    }
  }
  return result;
}

- (NSPredicate *)filterPredicate {
  if ([self.filters count] > 0)
    return [NSPredicate
        predicateWithFormat:@"SELF.path.pathExtension IN %@", self.filters];
  else
    return [NSPredicate predicateWithValue:YES];
}

- (void)setFilterPredicate:(NSPredicate *)newFilterPredicate {
  if (filterPredicate != newFilterPredicate) {
    filterPredicate = newFilterPredicate;
  }
}

- (IBAction)filterChanged:(id)sender {
  [self willChangeValueForKey:@"filters"];

  [self.filters removeAllObjects];
  NSInteger numSegments = [self.filterSegment segmentCount];

  for (NSInteger index = 0; index < numSegments; index++) {
    if ([self.filterSegment isSelectedForSegment:index]) {
      NSString *filterName = [self.filterSegment labelForSegment:index];
      [self.filters addObject:filterName];
      [self.filters addObject:[filterName uppercaseString]];
    }
  }

  [self didChangeValueForKey:@"filters"];
}

- (IBAction)removeImageCache:(id)sender {
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *cacheFile = [self imagesPlistFilePath];

  if ([fm fileExistsAtPath:cacheFile]) {
    [fm removeItemAtPath:cacheFile error:nil];
    [self findImagesShowingProgress:NO];
    self.imagePaths = [NSMutableArray array];
  }
}

- (IBAction)toggleHideDuplicates:(id)sender {
  self.hideDuplicates = !self.hideDuplicates;
  [[NSUserDefaults standardUserDefaults] setBool:self.hideDuplicates
                                          forKey:@"HideDuplicates"];
  if ([sender isKindOfClass:[NSMenuItem class]]) {
    NSMenuItem *item = (NSMenuItem *)sender;
    [item setTitle:(self.hideDuplicates ? @"Show Duplicates"
                                        : @"Hide Duplicates")];
    [item setState:(self.hideDuplicates ? NSControlStateValueOn
                                        : NSControlStateValueOff)];
  }
  [self willChangeValueForKey:@"imagePaths"];
  [self didChangeValueForKey:@"imagePaths"];
}

#pragma mark - Settings

- (IBAction)showPreferences:(id)sender {
  Class Prefs = NSClassFromString(@"JRSettings");
  if (!Prefs) {
    NSString *module =
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"]
            ?: @"";
    if (module.length == 0) {
      module =
          [[NSBundle
              mainBundle] objectForInfoDictionaryKey: @"CFBundleExecutable"]
              ?: @"";
    }
    if (module.length > 0) {
      NSString *qualified =
          [NSString stringWithFormat:@"%@.%@", module, @"JRSettings"];
      Prefs = NSClassFromString(qualified);
    }
  }
  SEL sharedSel = NSSelectorFromString(@"shared");
  if (Prefs && [Prefs respondsToSelector:sharedSel]) {
    id shared = ((id(*)(id, SEL))objc_msgSend)(Prefs, sharedSel);
    SEL showSel = NSSelectorFromString(@"showPreferences");
    if (shared && [shared respondsToSelector:showSel]) {
      ((void (*)(id, SEL))objc_msgSend)(shared, showSel);
    }
  }
}

- (void)settingsDidChange:(NSNotification *)note {
  // Debounced restart
  [self.rescanTimer invalidate];
  self.rescanTimer = [NSTimer
      scheduledTimerWithTimeInterval:0.5
                              target:self
                            selector:@selector(restartScanDueToSettings)
                            userInfo:nil
                             repeats:NO];
}

- (void)restartScanDueToSettings {
  // Apply updated settings
  self.hideDuplicates =
      [[NSUserDefaults standardUserDefaults] boolForKey:@"HideDuplicates"];
  // Stop current scan if running
  [JRScanServiceBridge stop];
  // Start a fresh scan; show progress if deep scan is enabled
  BOOL deepScan =
      [[NSUserDefaults standardUserDefaults] boolForKey:@"DeepScanEnabled"];
  [self findImagesShowingProgress:deepScan];
}

#pragma mark - Hashing

- (NSString *)sha256ForFileAtPath:(NSString *)path {
  if (!path)
    return nil;
  NSString *cached = [self.pathToHash objectForKey:path];
  if (cached)
    return cached;
  NSInputStream *stream = [NSInputStream inputStreamWithFileAtPath:path];
  if (!stream)
    return nil;
  [stream open];
  CC_SHA256_CTX ctx;
  CC_SHA256_Init(&ctx);
  uint8_t buffer[64 * 1024];
  NSInteger read = 0;
  while ((read = [stream read:buffer maxLength:sizeof(buffer)]) > 0) {
    CC_SHA256_Update(&ctx, buffer, (CC_LONG)read);
  }
  [stream close];
  if (read < 0)
    return nil;
  unsigned char digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256_Final(digest, &ctx);
  NSMutableString *hex =
      [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
  for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
    [hex appendFormat:@"%02x", digest[i]];
  }
  NSString *result = [hex copy];
  if (result) {
    [self.pathToHash setObject:result forKey:path];
  }
  return result;
}

@end
