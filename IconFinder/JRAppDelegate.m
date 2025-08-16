//
//  JRAppDelegate.m
//  IconFinder
//
//  Created by Joe on 6/24/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "JRAppDelegate.h"
#import "JRPreferencesController.h"
#import <CommonCrypto/CommonCrypto.h>


static NSString * const JRAppSettingsDidChangeNotification = @"AppSettingsDidChange";

@interface JRAppDelegate ()

@property (strong) NSMutableArray *imagePaths;
@property (assign) IBOutlet NSSegmentedControl *filterSegment;
@property (strong) NSMutableSet *filters;
@property (strong) NSPredicate *filterPredicate;
@property (readonly) NSMutableArray *filteredImagePaths;
@property (strong) NSTask *findTask;

// Dedupe support
@property (assign) BOOL hideDuplicates;
@property (strong) NSMutableDictionary<NSString*, NSString*> *pathToHash; // path -> sha256 hex

// Preferences
@property (strong) JRPreferencesController *preferencesController;
@property (strong) NSTimer *rescanTimer;

@end


@implementation JRAppDelegate

@synthesize window = _window;
@synthesize imagePaths;
@synthesize filterSegment;
@synthesize filters;
@synthesize filterPredicate;
@synthesize findTask;
@dynamic filteredImagePaths;

static NSArray *imageTypes;

+ (void)initialize
{
	imageTypes = [NSArray arrayWithObjects:@"jpeg", @"jpg", @"gif", @"png", @"icns", @"tiff", @"pdf", nil];
}

+ (NSSet *)keyPathsForValuesAffectingFilterPredicate
{
	return [NSSet setWithObjects:@"filters", nil];
}

+ (NSSet *)keyPathsForValuesAffectingImagePaths
{
	return [NSSet setWithObjects:@"filterPredicate", nil];
}

+(NSSet *)keyPathsForValuesAffectingFilteredImagePaths
{
	return [NSSet setWithObject:@"filterPredicate"];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	NSFileManager *fm = [NSFileManager defaultManager];
	// Observe settings changes
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(settingsDidChange:) name:JRAppSettingsDidChangeNotification object:nil];
	self.filters = [NSMutableSet set];
	self.filterPredicate = [NSPredicate predicateWithValue:YES];
	self.hideDuplicates = [[NSUserDefaults standardUserDefaults] boolForKey:@"HideDuplicates"];
	
	// Load hash cache if present
	if ([fm fileExistsAtPath:[self hashCacheFilePath]]) {
		NSDictionary *cache = [NSDictionary dictionaryWithContentsOfFile:[self hashCacheFilePath]];
		self.pathToHash = [cache mutableCopy];
	} else {
		self.pathToHash = [NSMutableDictionary dictionary];
	}
	
	if ([fm fileExistsAtPath:[self imagesPlistFilePath]])
	{
		self.imagePaths = [NSMutableArray arrayWithContentsOfFile:[self imagesPlistFilePath]];
	}
	else
	{
		self.imagePaths = [NSMutableArray array];
		[self findImages];
	}
	
	[self filterChanged:self.filterSegment];
}

- (void)findImages
{
	BOOL deepScan = [[NSUserDefaults standardUserDefaults] boolForKey:@"DeepScanEnabled"];
	NSAlert *searchingAlert = [[NSAlert alloc] init];
	searchingAlert.messageText = @"Searching your Mac for images";
	searchingAlert.informativeText = deepScan ? @"Deep Scan walks the filesystem and may take longer." : @"Using Spotlight for a fast, indexed search.";
	[searchingAlert addButtonWithTitle:@"Stop"];
	NSProgressIndicator *progIndicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(0, 0, 200, 32)];
	[progIndicator setIndeterminate:YES];
	[progIndicator setDisplayedWhenStopped:NO];
	[searchingAlert setAccessoryView:progIndicator];
	[searchingAlert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
		// User pressed Stop
		if (returnCode == NSAlertFirstButtonReturn) {
			if (self.findTask) {
				[self.findTask terminate];
			}
		}
	}];
	[progIndicator startAnimation:self];
	
	NSPipe *stdOut = [[NSPipe alloc] init];
	
	NSTask *find = [[NSTask alloc] init];
	if (deepScan) {
		// Deep scan: walk filesystem like original implementation (can be optimized later with allow/deny lists)
		[find setLaunchPath:@"/usr/bin/find"];
		NSString *arguments = @"/ -type f -and -name *.icns -or -name *.png -or -name *.tiff -or -name *.gif -or -name *.jpg -or -name *.jpeg -or -name *.pdf";
		[find setArguments:[arguments componentsSeparatedByString:@" "]];
	} else {
		// Fast scan: Spotlight
		[find setLaunchPath:@"/usr/bin/mdfind"];
		NSString *query = @"(kMDItemContentTypeTree == 'public.image' || kMDItemContentType == 'com.apple.icns' || kMDItemContentType == 'public.pdf' || kMDItemContentTypeTree == 'com.adobe.pdf')";
		[find setArguments:@[@"-onlyin", @"/", query]];
	}
	[find setStandardOutput:stdOut];
	self.findTask = find;
	
	NSFileHandle *fileHandle = [stdOut fileHandleForReading];
	
	NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
	
	[nc addObserverForName:NSFileHandleReadCompletionNotification object:fileHandle queue:nil usingBlock:^(NSNotification *note) {
		
		NSData *data = [[note userInfo] valueForKey:NSFileHandleNotificationDataItem];
		NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

		NSArray *paths  = [string componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
		
		for (NSString *path in paths)
		{
			if ([imageTypes containsObject:[path pathExtension]]) {
				[self.imagePaths addObject:path];
				
				searchingAlert.informativeText = [NSString stringWithFormat:@"%ld images found.", 
												  [self.imagePaths count]];
			}
		}
		
		if ([find isRunning])
			[fileHandle readInBackgroundAndNotify];
		else
		{
			[self writeImagePaths];
		}
		
	}];
	
	[nc addObserverForName:NSTaskDidTerminateNotification 
					object:find 
					 queue:nil 
				usingBlock:^(NSNotification *note) {
					
					[self willChangeValueForKey:@"imagePaths"];
					[self didChangeValueForKey:@"imagePaths"];
					[[searchingAlert window] orderOut:self];
					[self filterChanged:self.filterSegment];
					self.findTask = nil;
			
	}];
	
	[find launch];
	[fileHandle readInBackgroundAndNotify];
}


- (void)writeImagePaths
{
	NSFileManager *fm = [NSFileManager defaultManager];
	BOOL isDirectory = NO;
	NSString *appSupport = [NSHomeDirectory() stringByAppendingPathComponent:@"/Library/Application Support/IconFinder"];
	
	if ( !([fm fileExistsAtPath:appSupport isDirectory:&isDirectory] && isDirectory) )
	{
		[fm createDirectoryAtPath:appSupport withIntermediateDirectories:YES attributes:nil error:nil];
	}
	
	NSString *imagePathsFile = [appSupport stringByAppendingPathComponent:@"imagePaths.plist"];
	[self.imagePaths writeToFile:imagePathsFile atomically:YES];
	// Persist hash cache as well
	if (self.pathToHash) {
		[self.pathToHash writeToFile:[self hashCacheFilePath] atomically:YES];
	}
}

- (NSString*)imagesPlistFilePath
{
	return [NSHomeDirectory() stringByAppendingPathComponent:@"/Library/Application Support/IconFinder/imagePaths.plist"];
}

- (NSString*)hashCacheFilePath
{
	return [NSHomeDirectory() stringByAppendingPathComponent:@"/Library/Application Support/IconFinder/hashCache.plist"];
}

- (NSMutableArray*)filteredImagePaths
{
	NSArray *base = [self.imagePaths filteredArrayUsingPredicate:self.filterPredicate];
	if (!self.hideDuplicates) {
		return [base mutableCopy];
	}
	// Hide exact duplicates by SHA-256; keep first occurrence
	NSMutableArray *result = [NSMutableArray arrayWithCapacity:[base count]];
	NSMutableSet *seen = [NSMutableSet set];
	for (NSString *path in base) {
		NSString *hash = [self sha256ForFileAtPath:path];
		if (hash == nil) {
			[result addObject:path];
			continue;
		}
		if (![seen containsObject:hash]) {
			[seen addObject:hash];
			[result addObject:path];
		}
	}
	return result;
}

- (NSPredicate*)filterPredicate
{
	if ([self.filters count] > 0)
		return [NSPredicate predicateWithFormat:@"SELF.pathExtension IN %@", self.filters];
	else
		return [NSPredicate predicateWithValue:YES];
}

- (void)setFilterPredicate:(NSPredicate *)newFilterPredicate
{
	if (filterPredicate != newFilterPredicate)
	{
		filterPredicate = newFilterPredicate;
	}
}

- (IBAction)filterChanged:(id)sender
{
	[self willChangeValueForKey:@"filters"];
	
	[self.filters removeAllObjects];
	NSInteger numSegments = [self.filterSegment segmentCount];
	
	for (NSInteger index = 0; index < numSegments; index++)
	{
		if ([self.filterSegment isSelectedForSegment:index])
		{
			NSString *filterName = [self.filterSegment labelForSegment:index];
			[self.filters addObject:filterName];
			[self.filters addObject:[filterName uppercaseString]];
		}
	}
	
	[self didChangeValueForKey:@"filters"];
}

- (IBAction)removeImageCache:(id)sender
{
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *cacheFile = [self imagesPlistFilePath];
	
	if ([fm fileExistsAtPath:cacheFile])
	{
		[fm removeItemAtPath:cacheFile error:nil];
		[self findImages];
		self.imagePaths = [NSMutableArray array];
	}
}

- (IBAction)toggleHideDuplicates:(id)sender
{
	self.hideDuplicates = !self.hideDuplicates;
	[[NSUserDefaults standardUserDefaults] setBool:self.hideDuplicates forKey:@"HideDuplicates"];
	if ([sender isKindOfClass:[NSMenuItem class]]) {
		NSMenuItem *item = (NSMenuItem *)sender;
		[item setTitle:(self.hideDuplicates ? @"Show Duplicates" : @"Hide Duplicates")];
		[item setState:(self.hideDuplicates ? NSControlStateValueOn : NSControlStateValueOff)];
	}
	[self willChangeValueForKey:@"imagePaths"];
	[self didChangeValueForKey:@"imagePaths"];
}

#pragma mark - Settings

- (IBAction)showPreferences:(id)sender
{
	if (!self.preferencesController) {
		self.preferencesController = [[JRPreferencesController alloc] initWithWindowNibName:@"JRPreferences"];
	}
	[self.preferencesController showWindow:self];
	[NSApp activateIgnoringOtherApps:YES];
}

- (void)settingsDidChange:(NSNotification *)note
{
	// Debounced restart
	[self.rescanTimer invalidate];
	self.rescanTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(restartScanDueToSettings) userInfo:nil repeats:NO];
}

- (void)restartScanDueToSettings
{
	// Apply updated preferences
	self.hideDuplicates = [[NSUserDefaults standardUserDefaults] boolForKey:@"HideDuplicates"];
	// Stop current scan if running
	if (self.findTask) {
		[self.findTask terminate];
	}
	// Optionally clear current results to avoid mixing modes
	self.imagePaths = [NSMutableArray array];
	[self willChangeValueForKey:@"imagePaths"]; // trigger UI refresh
	[self didChangeValueForKey:@"imagePaths"];
	[self findImages];
}

#pragma mark - Hashing

- (NSString *)sha256ForFileAtPath:(NSString *)path
{
	if (!path) return nil;
	NSString *cached = [self.pathToHash objectForKey:path];
	if (cached) return cached;
	NSInputStream *stream = [NSInputStream inputStreamWithFileAtPath:path];
	if (!stream) return nil;
	[stream open];
	CC_SHA256_CTX ctx;
	CC_SHA256_Init(&ctx);
	uint8_t buffer[64 * 1024];
	NSInteger read = 0;
	while ((read = [stream read:buffer maxLength:sizeof(buffer)]) > 0) {
		CC_SHA256_Update(&ctx, buffer, (CC_LONG)read);
	}
	[stream close];
	if (read < 0) return nil;
	unsigned char digest[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256_Final(digest, &ctx);
	NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
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
