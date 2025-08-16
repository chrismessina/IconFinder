//
//  JRPreferencesController.m
//  IconFinder
//

#import "JRPreferencesController.h"
#import "JRConstants.h"

@implementation JRPreferencesController

- (void)windowDidLoad {
    [super windowDidLoad];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    BOOL deep = [d boolForKey:@"DeepScanEnabled"];
    BOOL hideDup = [d boolForKey:@"HideDuplicates"];
    self.deepScanSwitch.state = deep ? NSControlStateValueOn : NSControlStateValueOff;
    self.hideDupSwitch.state = hideDup ? NSControlStateValueOn : NSControlStateValueOff;
}

- (IBAction)deepScanToggled:(id)sender {
    BOOL on = ([(NSButton*)sender state] == NSControlStateValueOn);
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"DeepScanEnabled"];
    [[NSNotificationCenter defaultCenter] postNotificationName:JRAppSettingsDidChangeNotification object:self];
}

- (IBAction)hideDuplicatesToggled:(id)sender {
    BOOL on = ([(NSButton*)sender state] == NSControlStateValueOn);
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:@"HideDuplicates"];
    [[NSNotificationCenter defaultCenter] postNotificationName:JRAppSettingsDidChangeNotification object:self];
}

@end

