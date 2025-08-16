//
//  JRPreferencesController.h
//  IconFinder
#import <Cocoa/Cocoa.h>

@interface JRPreferencesController : NSWindowController

@property (weak) IBOutlet NSSwitch *deepScanSwitch;
@property (weak) IBOutlet NSSwitch *hideDupSwitch;

- (IBAction)deepScanToggled:(id)sender;
- (IBAction)hideDuplicatesToggled:(id)sender;

@end

