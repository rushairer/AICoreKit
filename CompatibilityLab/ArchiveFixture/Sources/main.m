#import <UIKit/UIKit.h>
#include <stdint.h>

extern int32_t AICKCoreAIIsAvailable(void)
    __attribute__((weak_import));

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    if (AICKCoreAIIsAvailable != NULL) {
        (void)AICKCoreAIIsAvailable();
    }
    return YES;
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(
            argc,
            argv,
            nil,
            NSStringFromClass([AppDelegate class])
        );
    }
}
