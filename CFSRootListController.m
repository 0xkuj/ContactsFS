#import <Foundation/Foundation.h>
#import <Contacts/Contacts.h>
#import "CFSRootListController.h"
#import "CFSTerminalViewController.h"

#pragma clang diagnostic ignored "-Wdeprecated-declarations"
@interface CNMutableContact (ContactsFS)
@property (nonatomic,copy) NSData* fullscreenImageData;
@end

@interface ContactImageProcessor : NSObject
+ (void)processAllContacts;
+ (NSData *)generateFullscreenImageDataFromThumbnail:(NSData *)thumbnailData;
+ (BOOL)shouldProcessContact:(CNContact *)contact;
+ (void)showAlert:(NSString *)message;
@end


@implementation CFSRootListController
- (NSArray *)specifiers {
	if (!_specifiers) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
	}

	return _specifiers;
}

- (IBAction)fixContacts:(id)sender {
	// Present terminal logger
	dispatch_async(dispatch_get_main_queue(), ^{
		UIViewController *presenting = self;
		while (presenting.presentedViewController) {
			presenting = presenting.presentedViewController;
		}
		CFSTerminalViewController *terminal = [CFSTerminalViewController shared];
		[terminal clear];
		if (presenting != terminal) {
			[presenting presentViewController:terminal animated:YES completion:nil];
		}
		[terminal appendLine:@"Starting contact processing..."];
        [terminal appendLine:@"*** PLEASE BE PATIENT, THIS MIGHT TAKE TIME (depends how much contacts needs to be updated)"];
	});
	
	CNContactStore *contactStore = [[CNContactStore alloc] init];
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		[CFSRootListController performContactProcessing:contactStore];
	});
}

+ (void)showAlert:(NSString *)message {
	// Route messages to terminal logger instead of alerts
	dispatch_async(dispatch_get_main_queue(), ^{
		[[CFSTerminalViewController shared] appendLine:message ?: @""];
	});
}

+ (void)processAllContacts {

}
+ (void)performContactProcessing:(CNContactStore *)contactStore {
	NSError *error = nil;
	NSArray *keys = @[
		CNContactIdentifierKey,
		CNContactGivenNameKey,
		CNContactFamilyNameKey,
		CNContactImageDataKey,
		CNContactImageDataAvailableKey,
		CNContactThumbnailImageDataKey
	];
	
	CNContactFetchRequest *fetchRequest = [[CNContactFetchRequest alloc] initWithKeysToFetch:keys];
	
	__block int processedCount = 0;
	__block NSMutableArray *contactsToUpdate = [[NSMutableArray alloc] init];
	
	[CFSRootListController showAlert:@"Starting enumeration of ALL contacts..."];
	
	// FIRST PASS: Enumerate ALL contacts and collect those that need updating
	BOOL success = [contactStore enumerateContactsWithFetchRequest:fetchRequest 
																	 error:&error 
																usingBlock:^(CNContact *contact, BOOL *stop) {
		@try {
			processedCount++;
			if (processedCount % 500 == 0) {
				NSString *progressMessage = [NSString stringWithFormat:@"Enumerating... processed %d contacts so far", processedCount];
				[CFSRootListController showAlert:progressMessage];
			}
			
			if ([CFSRootListController shouldProcessContact:contact]) {
				[contactsToUpdate addObject:contact];
			}
			
		} @catch (NSException *exception) {
			NSString *exceptionMessage = [NSString stringWithFormat:@"Exception during enumeration: %@", exception.reason];
			[CFSRootListController showAlert:exceptionMessage];
			*stop = YES;
		}
	}];
	
	if (!success) {
		NSString *errorMessage = [NSString stringWithFormat:@"Error fetching contacts: %@", error.localizedDescription];
		[CFSRootListController showAlert:errorMessage];
		return;
	}
	
	NSString *enumerationComplete = [NSString stringWithFormat:@"Enumeration complete! Found %lu contacts to update out of %d total contacts", (unsigned long)contactsToUpdate.count, processedCount];
	[CFSRootListController showAlert:enumerationComplete];
	
	// SECOND PASS: Update ALL collected contacts with adaptive pacing on a serial queue
	__block int updatedCount = 0;
	__block int failedCount = 0;
	__block int consecutiveSuccesses = 0;
	__block double currentDelaySeconds = 0.40; // slower baseline
	double const minDelay = 0.20;
	double const maxDelay = 1.00;
	double const stepDown = 0.01; // very gradual speed-up
	double const stepUp = 0.20;   // stronger slow-down on failures
	
	[CFSRootListController showAlert:@"Starting update process for all collected contacts..."];
	
	// Create serial queue to process updates one at a time
	dispatch_queue_t updateQueue = dispatch_queue_create("contact.update.queue", DISPATCH_QUEUE_SERIAL);
	
	for (int i = 0; i < contactsToUpdate.count; i++) {
		CNContact *contact = contactsToUpdate[i];
		
		// Safer initial staggering to avoid burst
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.05 * NSEC_PER_SEC)), updateQueue, ^{
			@autoreleasepool {
				@try {
					// Periodic rest every 100 updates
					if (updatedCount > 0 && (updatedCount % 100) == 0) {
						[CFSRootListController showAlert:@"Taking a short pause to keep things stable..."]; 
						[NSThread sleepForTimeInterval:2.0];
					}
					
					// Apply adaptive pacing before each update
					if (currentDelaySeconds > 0) {
						[NSThread sleepForTimeInterval:currentDelaySeconds];
					}
					BOOL ok = [CFSRootListController updateContactFullscreenImage:contact store:contactStore];
					if (ok) {
						updatedCount++;
						consecutiveSuccesses++;
						if (consecutiveSuccesses >= 15) { // require longer success streak to speed up
							currentDelaySeconds = MAX(minDelay, currentDelaySeconds - stepDown);
							consecutiveSuccesses = 0;
						}
						if (updatedCount % 25 == 0) {
							NSString *progressMsg = [NSString stringWithFormat:@"Updated %d/%lu contacts (delay %.0fms)", updatedCount, (unsigned long)contactsToUpdate.count, currentDelaySeconds * 1000.0];
							[CFSRootListController showAlert:progressMsg];
						}
					} else {
						failedCount++;
						consecutiveSuccesses = 0;
						currentDelaySeconds = MIN(maxDelay, currentDelaySeconds + stepUp);
						// brief extra wait after a failure to let things settle
						[NSThread sleepForTimeInterval:0.5];
					}
					
					// Show completion when all are done
					if ((updatedCount + failedCount) == contactsToUpdate.count) {
						NSString *completionMessage = [NSString stringWithFormat:@"COMPLETED! Processed %d total contacts, Updated %d contacts, Failed %d contacts", processedCount, updatedCount, failedCount];
						[CFSRootListController showAlert:completionMessage];
						[[CFSTerminalViewController shared] markCompleted];
					}
					
				} @catch (NSException *exception) {
					failedCount++;
					consecutiveSuccesses = 0;
					currentDelaySeconds = MIN(maxDelay, currentDelaySeconds + stepUp);
					NSString *exceptionMessage = [NSString stringWithFormat:@"Exception updating contact: %@", exception.reason];
					[CFSRootListController showAlert:exceptionMessage];
					[NSThread sleepForTimeInterval:0.5];
				}
			}
		});
	}
}

+ (BOOL)shouldProcessContact:(CNContact *)contact {
	// Only process contacts that have imageData but might be missing fullscreen data
	return contact.imageDataAvailable && contact.imageData && contact.imageData.length > 0;
}

+ (BOOL)updateContactFullscreenImage:(CNContact *)contact store:(CNContactStore *)contactStore {
	@try {
		CNMutableContact *mutableContact = [contact mutableCopy];
		NSData *fullscreenData = contact.imageData != nil ? [CFSRootListController generateFullscreenImageDataFromThumbnail:contact.imageData] : [CFSRootListController generateFullscreenImageDataFromThumbnail:contact.thumbnailImageData];
	
		if (!fullscreenData) {
			[CFSRootListController showAlert:@"Failed to generate fullscreen data for contact"];
			return NO;
		}
		
		mutableContact.imageData = fullscreenData;
		CNSaveRequest *saveRequest = [[CNSaveRequest alloc] init];
		[saveRequest updateContact:mutableContact];
		NSError *saveError = nil;
		BOOL success = [contactStore executeSaveRequest:saveRequest error:&saveError];
		
		if (!success) {
			NSString *errorMessage = [NSString stringWithFormat:@"Failed to save contact: %@", saveError.localizedDescription];
			[CFSRootListController showAlert:errorMessage];
			return NO;
		}
		
		return YES;
		
	} @catch (NSException *exception) {
		NSString *exceptionMessage = [NSString stringWithFormat:@"Exception updating contact: %@", exception.reason];
		[CFSRootListController showAlert:exceptionMessage];
		return NO;
	}
}

+ (NSData *)generateFullscreenImageDataFromThumbnail:(NSData *)thumbnailData {
	if (!thumbnailData || thumbnailData.length == 0) {
		[CFSRootListController showAlert:@"thumbnail is nil.."]; 
		return nil;
	}
	
	UIImage *originalImage = [UIImage imageWithData:thumbnailData];
	if (!originalImage) {
		[CFSRootListController showAlert:@"image is nil.."]; 
		return nil;
	}
	
	NSData *scaledImage = [CFSRootListController scaleImage:originalImage toSize:CGSizeMake([UIScreen mainScreen].bounds.size.width,[UIScreen mainScreen].bounds.size.height)];
	
	return scaledImage;
}

+ (NSData *)scaleImage:(UIImage*)image toSize:(CGSize)newSize {
	CGSize imageSize = image.size;
	CGFloat newWidth  = newSize.width  / image.size.width;
	CGFloat newHeight = newSize.height / image.size.height;
	CGSize newImgSize;

	if(newWidth > newHeight) {
		newImgSize = CGSizeMake(imageSize.width * newHeight, imageSize.height * newHeight);
	} else {
		newImgSize = CGSizeMake(imageSize.width * newWidth,  imageSize.height * newWidth);
	}

	CGRect rect = CGRectMake(0, 0, newImgSize.width, newImgSize.height);
	UIGraphicsBeginImageContextWithOptions(newImgSize, false, 0.0);
	[image drawInRect:rect];
	UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();

	return UIImageJPEGRepresentation(newImage, 1.0);
}

-(void)openTwitter {
	UIApplication *application = [UIApplication sharedApplication];
	NSURL *URL = [NSURL URLWithString:@"https://www.twitter.com/0xkuj"];
	[application openURL:URL options:@{} completionHandler:^(BOOL success) {return;}];
}

-(void)donationLink {
	UIApplication *application = [UIApplication sharedApplication];
	NSURL *URL = [NSURL URLWithString:@"https://www.paypal.me/0xkuj"];
	[application openURL:URL options:@{} completionHandler:^(BOOL success) {return;}];
}

-(void)openGithub {
	UIApplication *application = [UIApplication sharedApplication];
	NSURL *URL = [NSURL URLWithString:@"https://github.com/0xkuj/..."];
	[application openURL:URL options:@{} completionHandler:^(BOOL success) {return;}];
}
@end
