#import "CFSTerminalViewController.h"

@interface CFSTerminalViewController ()
@property (nonatomic, strong) UITextView *textView;
@end

@implementation CFSTerminalViewController

+ (instancetype)shared {
	static CFSTerminalViewController *sharedInstance = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedInstance = [[self alloc] init];
	});
	return sharedInstance;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [UIColor blackColor];

	self.textView = [[UITextView alloc] initWithFrame:self.view.bounds];
	self.textView.backgroundColor = [UIColor clearColor];
	self.textView.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
	self.textView.editable = NO;
	self.textView.selectable = NO;
	self.textView.alwaysBounceVertical = YES;
	self.textView.textContainerInset = UIEdgeInsetsMake(16, 16, 16, 16);
	self.textView.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
	self.textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	[self.view addSubview:self.textView];
}

- (void)appendLine:(NSString *)line {
	if (line.length == 0) { return; }
	dispatch_async(dispatch_get_main_queue(), ^{
		NSString *current = self.textView.text ?: @"";
		NSString *newLine = [current length] > 0 ? [current stringByAppendingFormat:@"\n%@", line] : line;
		self.textView.text = newLine;
		NSRange bottom = NSMakeRange(self.textView.text.length - 1, 1);
		[self.textView scrollRangeToVisible:bottom];
	});
}

- (void)clear {
	dispatch_async(dispatch_get_main_queue(), ^{
		self.textView.text = @"";
	});
}

- (void)markCompleted {
	[self appendLine:@"\n\n[✔] Completed."];
}

@end 