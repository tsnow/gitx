//
//  PBGitSVRemoteItem.h
//  GitX
//
//  Created by Nathan Kinsinger on 3/2/10.
//  Copyright 2010 Nathan Kinsinger. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "PBSourceViewItem.h"


@interface PBGitSVRemoteItem : PBSourceViewItem {
}

@property (assign) BOOL loading;
@property (assign) BOOL alert;
@property (strong) NSString *helpText;

+ (id)remoteItemWithTitle:(NSString *)title;

@end
