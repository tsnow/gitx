//
//  PBGitHistoryView.h
//  GitX
//
//  Created by David Catmull on 20-06-11.
//  Copyright 2011. All rights reserved.
//

#import "PBViewController.h"

// Controls the view displaying a stash diff
@interface PBGitStashController : PBViewController {
	IBOutlet id webView;
	IBOutlet PBWebStashController *webHistoryController;
}

- (void) c:(PBGitStash)stash;

@end

@interface PBWebStashController : PBWebController {
	PBGitStash* currentStash;
	NSString* diff;
}

- (void) changeContentTo:(PBGitStash*)stash;

@property (readonly) NSString* diff;

@end
