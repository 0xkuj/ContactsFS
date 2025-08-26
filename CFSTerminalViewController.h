#import <UIKit/UIKit.h>

@interface CFSTerminalViewController : UIViewController

+ (instancetype)shared;
- (void)appendLine:(NSString *)line;
- (void)clear;
- (void)markCompleted;

@end 