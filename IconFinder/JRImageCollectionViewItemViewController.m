//
//  JRImageCollectionViewItemViewController.m
//  IconFinder
//
//  Created by Joe on 6/25/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "JRImageCollectionViewItemViewController.h"
#import "JRThumbnailCache.h"

@interface JRImageCollectionViewItemViewController ()

@end

@implementation JRImageCollectionViewItemViewController

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self)
    {
    }
    return self;
}

- (void)loadView
{
    NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 120)];
    root.wantsLayer = YES;
    root.translatesAutoresizingMaskIntoConstraints = NO;

    NSImageView *iv = [[NSImageView alloc] initWithFrame:NSZeroRect];
    iv.translatesAutoresizingMaskIntoConstraints = NO;
    iv.imageScaling = NSImageScaleProportionallyUpOrDown;
    iv.imageAlignment = NSImageAlignCenter;
    [root addSubview:iv];
    self.imageView = iv;

    NSTextField *label = [NSTextField labelWithString:@""];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.lineBreakMode = NSLineBreakByTruncatingMiddle;
    label.alignment = NSTextAlignmentCenter;
    [root addSubview:label];
    self.textField = label;

    // Constraints: image view top/leading/trailing; height == width; label below with padding
    [NSLayoutConstraint activateConstraints:@[
        [iv.topAnchor constraintEqualToAnchor:root.topAnchor constant:6],
        [iv.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:6],
        [iv.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-6],
        [iv.heightAnchor constraintEqualToAnchor:iv.widthAnchor],

        [label.topAnchor constraintEqualToAnchor:iv.bottomAnchor constant:4],
        [label.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:4],
        [label.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-4],
        [label.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-6]
    ]];

    self.view = root;
}

- (void)setRepresentedObject:(id)representedObject
{
    [super setRepresentedObject:representedObject];
    NSString *path = nil;
    if ([representedObject isKindOfClass:[NSString class]]) {
        path = (NSString *)representedObject;
    } else if ([representedObject isKindOfClass:[NSURL class]]) {
        path = [(NSURL *)representedObject path];
    } else if ([representedObject respondsToSelector:@selector(path)]) {
        @try { path = [representedObject valueForKey:@"path"]; } @catch (...) { path = nil; }
    }
    if (path) {
        // Set label immediately; load thumbnail asynchronously
        self.textField.stringValue = [path lastPathComponent];
        __unsafe_unretained typeof(self) weakSelf = self;
        NSString *currentPath = [path copy];
        // Compute a target thumbnail size that matches our layout item size minus padding
        CGFloat width = 88.0; // matches flow layout image height approximation
        CGSize thumbSize = CGSizeMake(width, width);
        // Defer to thumbnail cache
        JRThumbnailCache *cache = [JRThumbnailCache shared];
        [cache thumbnailForPath:currentPath size:thumbSize completion:^(NSImage *img){
            __strong typeof(weakSelf) selfStrong = weakSelf;
            if (!selfStrong) return;
            NSString *repPath = nil;
            if ([selfStrong.representedObject isKindOfClass:[NSString class]]) {
                repPath = (NSString *)selfStrong.representedObject;
            } else if ([selfStrong.representedObject isKindOfClass:[NSURL class]]) {
                repPath = [(NSURL *)selfStrong.representedObject path];
            } else if ([selfStrong.representedObject respondsToSelector:@selector(path)]) {
                @try { repPath = [selfStrong.representedObject valueForKey:@"path"]; } @catch (...) { repPath = nil; }
            }
            if ([repPath isEqualToString:currentPath]) {
                selfStrong.imageView.image = img;
            }
        }];
    } else {
        self.imageView.image = nil;
        self.textField.stringValue = @"";
    }
}

- (void)setSelected:(BOOL)selected
{
    [super setSelected:selected];
    if (self.view.wantsLayer == NO) { self.view.wantsLayer = YES; }
    if (selected) {
        self.view.layer.cornerRadius = 8.0;
        self.view.layer.masksToBounds = YES;
        if (@available(macOS 11.0, *)) {
            self.view.layer.backgroundColor = NSColor.selectedContentBackgroundColor.CGColor;
        } else {
            self.view.layer.backgroundColor = [NSColor selectedControlColor].CGColor;
        }
        self.textField.textColor = [NSColor selectedTextColor];
    } else {
        self.view.layer.backgroundColor = [NSColor clearColor].CGColor;
        self.textField.textColor = [NSColor labelColor];
    }
}

@end
