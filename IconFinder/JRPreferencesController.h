//
//  JRPreferencesController.h
//  IconFinder
#import <Cocoa/Cocoa.h>

@interface JRPreferencesController : NSWindowController

@property (weak) IBOutlet NSButton *deepScanSwitch;
@property (weak) IBOutlet NSButton *hideDupSwitch;

- (IBAction)deepScanToggled:(id)sender;
- (IBAction)hideDuplicatesToggled:(id)sender;

@end

