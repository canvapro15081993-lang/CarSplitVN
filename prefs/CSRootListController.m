#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID;
@end

@interface CSRootListController : PSListController
@end

@implementation CSRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)openCarSplitApp {
    [[LSApplicationWorkspace defaultWorkspace] openApplicationWithBundleID:@"vn.carsplit.roothide.app"];
}

@end
